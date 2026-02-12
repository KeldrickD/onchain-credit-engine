// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILoanEngine} from "./interfaces/ILoanEngine.sol";
import {ICreditRegistry} from "./interfaces/ICreditRegistry.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IPriceRouter} from "./interfaces/IPriceRouter.sol";
import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IRiskOracle} from "./interfaces/IRiskOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InterestRateModel} from "./InterestRateModel.sol";

/// @title LoanEngine
/// @notice Multi-collateral borrow flow: PriceRouter + CollateralManager + CreditRegistry → LoanEngine.
/// @dev Index-based debt accrual. One position per borrower, single collateral asset per position.
contract LoanEngine is ILoanEngine, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365.25 days;
    uint256 private constant USD8_TO_USDC6 = 100;

    uint256 private constant NUM_TIERS = 4;

    ICreditRegistry public immutable creditRegistry;
    ITreasuryVault public immutable treasuryVault;
    IPriceRouter public immutable priceRouter;
    ICollateralManager public immutable collateralManager;
    IERC20 public immutable usdc;

    mapping(address => mapping(address => uint256)) private collateralBalances;
    mapping(address => address) private positionCollateralAsset;
    mapping(address => uint256) private positionCollateralAmount;

    struct PositionStorage {
        uint256 openedAt;
        uint256 ltvBps;
        uint256 interestRateBps;
        uint256 scaledDebtRay;
        uint256 userTier;
    }
    mapping(address => PositionStorage) private positions;

    mapping(uint256 => uint256) private borrowIndexRay;
    mapping(uint256 => uint256) private lastAccrualTimestamp;

    event CollateralDeposited(address indexed user, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event LoanOpened(
        address indexed borrower,
        address indexed asset,
        uint256 collateralAmount,
        uint256 principalAmount,
        uint256 ltvBps,
        uint256 interestRateBps
    );
    event LoanRepaid(address indexed borrower, uint256 amount, uint256 remainingPrincipal);

    error LoanEngine_ZeroAmount();
    error LoanEngine_InsufficientCollateral();
    error LoanEngine_BorrowExceedsMax();
    error LoanEngine_ActiveLoanExists();
    error LoanEngine_InvalidPayloadUser();
    error LoanEngine_InsufficientVaultLiquidity();
    error LoanEngine_RepayExceedsPrincipal();
    error LoanEngine_WithdrawWouldViolateLTV();
    error LoanEngine_WithdrawWouldViolateLiquidationThreshold();
    error LoanEngine_OnlyLiquidationManager();
    error LoanEngine_AssetNotEnabled();
    error LoanEngine_PriceStale();

    event LiquidationManagerSet(address indexed oldManager, address indexed newManager);
    event LiquidationRepay(address indexed borrower, uint256 amount, uint256 remainingPrincipal);
    event CollateralSeized(address indexed borrower, address indexed to, uint256 amount);

    address public liquidationManager;

    constructor(
        address _creditRegistry,
        address _treasuryVault,
        address _usdc,
        address _priceRouter,
        address _collateralManager
    ) Ownable(msg.sender) {
        creditRegistry = ICreditRegistry(_creditRegistry);
        treasuryVault = ITreasuryVault(_treasuryVault);
        usdc = IERC20(_usdc);
        priceRouter = IPriceRouter(_priceRouter);
        collateralManager = ICollateralManager(_collateralManager);
        for (uint256 i = 0; i < NUM_TIERS; i++) {
            borrowIndexRay[i] = RAY;
            lastAccrualTimestamp[i] = block.timestamp;
        }
    }

    function depositCollateral(address asset, uint256 amount) external override nonReentrant {
        if (amount == 0) revert LoanEngine_ZeroAmount();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        collateralBalances[msg.sender][asset] += amount;
        emit CollateralDeposited(msg.sender, asset, amount);
    }

    function withdrawCollateral(address asset, uint256 amount) external override nonReentrant {
        if (amount == 0) revert LoanEngine_ZeroAmount();
        if (collateralBalances[msg.sender][asset] < amount) revert LoanEngine_InsufficientCollateral();

        PositionStorage storage pos = positions[msg.sender];
        if (pos.scaledDebtRay > 0) {
            address posAsset = positionCollateralAsset[msg.sender];
            if (posAsset == asset) {
                _accrueTier(pos.userTier);
                uint256 currentDebt = (pos.scaledDebtRay * borrowIndexRay[pos.userTier]) / RAY;
                uint256 remaining = collateralBalances[msg.sender][asset] - amount;
                uint256 maxDebtLTV = _getMaxBorrowUSDC6(msg.sender, asset, remaining);
                if (currentDebt > maxDebtLTV) revert LoanEngine_WithdrawWouldViolateLTV();
                uint256 maxDebtLiq = _getMaxDebtForLiquidationSafety(asset, remaining);
                if (currentDebt > maxDebtLiq) revert LoanEngine_WithdrawWouldViolateLiquidationThreshold();
            }
        }

        collateralBalances[msg.sender][asset] -= amount;
        if (positionCollateralAsset[msg.sender] == asset) {
            positionCollateralAmount[msg.sender] -= amount;
        }
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, asset, amount);
    }

    function openLoan(
        address asset,
        uint256 borrowAmountUSDC6,
        IRiskOracle.RiskPayload calldata payload,
        bytes calldata signature
    ) external override nonReentrant {
        if (borrowAmountUSDC6 == 0) revert LoanEngine_ZeroAmount();
        if (payload.user != msg.sender) revert LoanEngine_InvalidPayloadUser();

        PositionStorage storage pos = positions[msg.sender];
        if (pos.scaledDebtRay > 0) revert LoanEngine_ActiveLoanExists();

        ICollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(asset);
        if (!cfg.enabled) revert LoanEngine_AssetNotEnabled();

        (uint256 priceUSD8,, bool isStale) = priceRouter.getPriceUSD8(asset);
        if (isStale || priceUSD8 == 0) revert LoanEngine_PriceStale();

        creditRegistry.updateCreditProfile(payload, signature);

        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(msg.sender);
        (uint256 scoreLtvBps, uint256 rateBps) = _getTermsFromScore(profile.score);
        uint256 tier = InterestRateModel.getTierFromScore(profile.score);

        _accrueTier(tier);

        uint256 coll = collateralBalances[msg.sender][asset];
        uint256 maxBorrow = getMaxBorrow(msg.sender, asset);
        if (borrowAmountUSDC6 > maxBorrow) revert LoanEngine_BorrowExceedsMax();

        uint256 vaultBalance = usdc.balanceOf(address(treasuryVault));
        if (borrowAmountUSDC6 > vaultBalance) revert LoanEngine_InsufficientVaultLiquidity();

        collateralManager.increaseDebt(asset, uint128(borrowAmountUSDC6));

        uint256 effectiveLtv = _effectiveLtvBps(scoreLtvBps, cfg.ltvBpsCap);
        uint256 idx = borrowIndexRay[tier];
        uint256 scaledDebt = (borrowAmountUSDC6 * RAY) / idx;

        positions[msg.sender] = PositionStorage({
            openedAt: block.timestamp,
            ltvBps: effectiveLtv,
            interestRateBps: rateBps,
            scaledDebtRay: scaledDebt,
            userTier: tier
        });
        positionCollateralAsset[msg.sender] = asset;
        positionCollateralAmount[msg.sender] = coll;

        treasuryVault.transferToBorrower(msg.sender, borrowAmountUSDC6);
        emit LoanOpened(msg.sender, asset, coll, borrowAmountUSDC6, effectiveLtv, rateBps);
    }

    function repay(uint256 amount) external override nonReentrant {
        if (amount == 0) revert LoanEngine_ZeroAmount();

        PositionStorage storage pos = positions[msg.sender];
        address asset = positionCollateralAsset[msg.sender];
        _accrueTier(pos.userTier);

        uint256 idx = borrowIndexRay[pos.userTier];
        uint256 currentDebt = (pos.scaledDebtRay * idx) / RAY;
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

        treasuryVault.pullFromBorrower(msg.sender, repayAmount);

        collateralManager.decreaseDebt(asset, uint128(repayAmount));
        pos.scaledDebtRay -= (repayAmount * RAY) / idx;
        uint256 remaining = (pos.scaledDebtRay * idx) / RAY;
        emit LoanRepaid(msg.sender, repayAmount, remaining);
    }

    function getTerms(address user) external view override returns (LoanTerms memory) {
        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(user);
        (uint256 ltvBps, uint256 rateBps) = _getTermsFromScore(profile.score);
        return LoanTerms({ltvBps: ltvBps, interestRateBps: rateBps});
    }

    function getPosition(address user) external view override returns (LoanPosition memory) {
        PositionStorage storage pos = positions[user];
        uint256 principalAmount = 0;
        if (pos.scaledDebtRay > 0) {
            uint256 idx = _getBorrowIndexRayView(pos.userTier);
            principalAmount = (pos.scaledDebtRay * idx) / RAY;
        }
        return LoanPosition({
            collateralAsset: positionCollateralAsset[user],
            collateralAmount: positionCollateralAmount[user],
            principalAmount: principalAmount,
            openedAt: pos.openedAt,
            ltvBps: pos.ltvBps,
            interestRateBps: pos.interestRateBps
        });
    }

    function getCollateralBalance(address user, address asset) external view override returns (uint256) {
        return collateralBalances[user][asset];
    }

    function getPositionCollateralAsset(address user) external view override returns (address) {
        return positionCollateralAsset[user];
    }

    function getMaxBorrow(address user, address asset) public view override returns (uint256) {
        return _getMaxBorrowUSDC6(user, asset, collateralBalances[user][asset]);
    }

    function setLiquidationManager(address _liquidationManager) external onlyOwner {
        address old = liquidationManager;
        liquidationManager = _liquidationManager;
        emit LiquidationManagerSet(old, _liquidationManager);
    }

    modifier onlyLiquidationManager() {
        if (msg.sender != liquidationManager) revert LoanEngine_OnlyLiquidationManager();
        _;
    }

    function liquidationRepay(address borrower, uint256 amount)
        external
        override
        onlyLiquidationManager
        nonReentrant
    {
        if (amount == 0) revert LoanEngine_ZeroAmount();

        PositionStorage storage pos = positions[borrower];
        address asset = positionCollateralAsset[borrower];
        _accrueTier(pos.userTier);

        uint256 idx = borrowIndexRay[pos.userTier];
        uint256 currentDebt = (pos.scaledDebtRay * idx) / RAY;
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

        pos.scaledDebtRay -= (repayAmount * RAY) / idx;
        collateralManager.decreaseDebt(asset, uint128(repayAmount));
        uint256 remaining = (pos.scaledDebtRay * idx) / RAY;
        emit LiquidationRepay(borrower, repayAmount, remaining);
    }

    function seizeCollateral(address borrower, address to, uint256 amount)
        external
        override
        onlyLiquidationManager
        nonReentrant
    {
        if (amount == 0) revert LoanEngine_ZeroAmount();
        address asset = positionCollateralAsset[borrower];
        if (collateralBalances[borrower][asset] < amount) revert LoanEngine_InsufficientCollateral();

        collateralBalances[borrower][asset] -= amount;
        positionCollateralAmount[borrower] -= amount;
        IERC20(asset).safeTransfer(to, amount);

        emit CollateralSeized(borrower, to, amount);
    }

    // -------------------------------------------------------------------------
    // Valuation helpers
    // -------------------------------------------------------------------------

    function _getValueUSDC6(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;
        (uint256 priceUSD8,,) = priceRouter.getPriceUSD8(asset);
        if (priceUSD8 == 0) return 0;
        uint8 dec = IERC20Metadata(asset).decimals();
        uint256 valueUSD8 = (amount * priceUSD8) / (10 ** dec);
        return valueUSD8 / USD8_TO_USDC6;
    }

    function _getMaxBorrowUSDC6(address user, address asset, uint256 collateralAmount)
        internal
        view
        returns (uint256)
    {
        if (collateralAmount == 0) return 0;

        ICollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(asset);
        if (!cfg.enabled) return 0;

        (uint256 priceUSD8,, bool isStale) = priceRouter.getPriceUSD8(asset);
        if (isStale || priceUSD8 == 0) return 0;

        uint256 valueUSDC6 = _getValueUSDC6(asset, collateralAmount);
        uint256 valueAfterHaircut = (valueUSDC6 * cfg.haircutBps) / BPS;

        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(user);
        (uint256 scoreLtvBps,) = _getTermsFromScore(profile.score);
        uint256 ltvBps = _effectiveLtvBps(scoreLtvBps, cfg.ltvBpsCap);

        return (valueAfterHaircut * ltvBps) / BPS;
    }

    function _effectiveLtvBps(uint256 scoreLtvBps, uint16 capBps) internal pure returns (uint256) {
        if (capBps == 0) return scoreLtvBps;
        return scoreLtvBps < capBps ? scoreLtvBps : capBps;
    }

    /// @dev Max debt that keeps position above liquidation threshold (for withdrawal safety)
    function _getMaxDebtForLiquidationSafety(address asset, uint256 collateralAmount)
        internal
        view
        returns (uint256)
    {
        if (collateralAmount == 0) return 0;
        ICollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(asset);
        if (!cfg.enabled) return 0;
        (uint256 priceUSD8,, bool isStale) = priceRouter.getPriceUSD8(asset);
        if (isStale || priceUSD8 == 0) return 0;

        uint256 valueUSDC6 = _getValueUSDC6(asset, collateralAmount);
        uint256 valueAfterHaircut = (valueUSDC6 * cfg.haircutBps) / BPS;

        uint256 liqThresholdBps = cfg.liquidationThresholdBpsCap;
        if (liqThresholdBps == 0) liqThresholdBps = 8800;
        return (valueAfterHaircut * liqThresholdBps) / BPS;
    }

    // -------------------------------------------------------------------------
    // Accrual
    // -------------------------------------------------------------------------

    function _accrueTier(uint256 tier) internal {
        uint256 last = lastAccrualTimestamp[tier];
        if (block.timestamp <= last) return;

        uint256 elapsed = block.timestamp - last;
        uint256 rateBps = InterestRateModel.rateBpsForTier(tier);
        uint256 multiplierRay = RAY + (rateBps * RAY / BPS) * elapsed / SECONDS_PER_YEAR;
        borrowIndexRay[tier] = (borrowIndexRay[tier] * multiplierRay) / RAY;
        lastAccrualTimestamp[tier] = block.timestamp;
    }

    function _getBorrowIndexRayView(uint256 tier) internal view returns (uint256) {
        uint256 idx = borrowIndexRay[tier];
        uint256 last = lastAccrualTimestamp[tier];
        if (block.timestamp <= last) return idx;

        uint256 elapsed = block.timestamp - last;
        uint256 rateBps = InterestRateModel.rateBpsForTier(tier);
        uint256 multiplierRay = RAY + (rateBps * RAY / BPS) * elapsed / SECONDS_PER_YEAR;
        return (idx * multiplierRay) / RAY;
    }

    function _getTermsFromScore(uint256 score)
        internal
        pure
        returns (uint256 ltvBps, uint256 interestRateBps)
    {
        if (score >= 851) return (8500, 500);
        if (score >= 700) return (7500, 700);
        if (score >= 400) return (6500, 1000);
        return (5000, 1500);
    }
}
