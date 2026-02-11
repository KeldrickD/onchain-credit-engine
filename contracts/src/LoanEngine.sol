// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILoanEngine} from "./interfaces/ILoanEngine.sol";
import {ICreditRegistry} from "./interfaces/ICreditRegistry.sol";
import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IRiskOracle} from "./interfaces/IRiskOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LoanEngine
/// @notice MVP borrow flow: RiskOracle → CreditRegistry → LoanEngine → TreasuryVault → USDC
/// @dev Single loan per borrower. Collateral held in LoanEngine. Repay via vault.pullFromBorrower.
contract LoanEngine is ILoanEngine, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants — Score → Terms (v0 hard-coded curve)
    // -------------------------------------------------------------------------
    // 0–399:   LTV 50%,  rate 1500 bps
    // 400–699: LTV 65%,  rate 1000 bps
    // 700–850: LTV 75%,  rate 700 bps
    // 851–1000: LTV 85%, rate 500 bps

    uint256 private constant BPS = 10_000;
    uint256 private constant COLLATERAL_TO_USDC = 1e12; // 18 - 6 decimals

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    ICreditRegistry public immutable creditRegistry;
    ITreasuryVault public immutable treasuryVault;
    IERC20 public immutable usdc;
    IERC20 public immutable collateral;

    mapping(address => uint256) private collateralBalances;
    mapping(address => LoanPosition) private positions;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event LoanOpened(
        address indexed borrower,
        uint256 collateralAmount,
        uint256 principalAmount,
        uint256 ltvBps,
        uint256 interestRateBps
    );
    event LoanRepaid(address indexed borrower, uint256 amount, uint256 remainingPrincipal);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error LoanEngine_ZeroAmount();
    error LoanEngine_InsufficientCollateral();
    error LoanEngine_BorrowExceedsMax();
    error LoanEngine_ActiveLoanExists();
    error LoanEngine_InvalidPayloadUser();
    error LoanEngine_InsufficientVaultLiquidity();
    error LoanEngine_RepayExceedsPrincipal();
    error LoanEngine_WithdrawWouldViolateLTV();
    error LoanEngine_OnlyLiquidationManager();

    event LiquidationManagerSet(address indexed oldManager, address indexed newManager);
    event LiquidationRepay(address indexed borrower, uint256 amount, uint256 remainingPrincipal);
    event CollateralSeized(address indexed borrower, address indexed to, uint256 amount);

    address public liquidationManager;

    constructor(
        address _creditRegistry,
        address _treasuryVault,
        address _usdc,
        address _collateral
    ) Ownable(msg.sender) {
        creditRegistry = ICreditRegistry(_creditRegistry);
        treasuryVault = ITreasuryVault(_treasuryVault);
        usdc = IERC20(_usdc);
        collateral = IERC20(_collateral);
    }

    // -------------------------------------------------------------------------
    // External
    // -------------------------------------------------------------------------

    /// @inheritdoc ILoanEngine
    function depositCollateral(uint256 amount) external override nonReentrant {
        if (amount == 0) revert LoanEngine_ZeroAmount();

        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateralBalances[msg.sender] += amount;

        emit CollateralDeposited(msg.sender, amount);
    }

    /// @inheritdoc ILoanEngine
    function withdrawCollateral(uint256 amount) external override nonReentrant {
        if (amount == 0) revert LoanEngine_ZeroAmount();
        if (collateralBalances[msg.sender] < amount) revert LoanEngine_InsufficientCollateral();

        LoanPosition memory pos = positions[msg.sender];

        if (pos.principalAmount > 0) {
            uint256 remaining = collateralBalances[msg.sender] - amount;
            uint256 maxDebtUsdc = (remaining * pos.ltvBps) / BPS / COLLATERAL_TO_USDC;
            if (pos.principalAmount > maxDebtUsdc) revert LoanEngine_WithdrawWouldViolateLTV();
        }

        collateralBalances[msg.sender] -= amount;
        collateral.safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @inheritdoc ILoanEngine
    function openLoan(
        uint256 borrowAmount,
        IRiskOracle.RiskPayload calldata payload,
        bytes calldata signature
    ) external override nonReentrant {
        if (borrowAmount == 0) revert LoanEngine_ZeroAmount();
        if (payload.user != msg.sender) revert LoanEngine_InvalidPayloadUser();

        LoanPosition storage pos = positions[msg.sender];
        if (pos.principalAmount > 0) revert LoanEngine_ActiveLoanExists();

        creditRegistry.updateCreditProfile(payload, signature);

        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(msg.sender);
        (uint256 ltvBps, uint256 rateBps) = _getTermsFromScore(profile.score);

        uint256 coll = collateralBalances[msg.sender];
        uint256 maxBorrow = (coll * ltvBps) / BPS / COLLATERAL_TO_USDC;
        if (borrowAmount > maxBorrow) revert LoanEngine_BorrowExceedsMax();

        uint256 vaultBalance = usdc.balanceOf(address(treasuryVault));
        if (borrowAmount > vaultBalance) revert LoanEngine_InsufficientVaultLiquidity();

        positions[msg.sender] = LoanPosition({
            collateralAmount: coll,
            principalAmount: borrowAmount,
            openedAt: block.timestamp,
            ltvBps: ltvBps,
            interestRateBps: rateBps
        });

        treasuryVault.transferToBorrower(msg.sender, borrowAmount);

        emit LoanOpened(msg.sender, coll, borrowAmount, ltvBps, rateBps);
    }

    /// @inheritdoc ILoanEngine
    function repay(uint256 amount) external override nonReentrant {
        if (amount == 0) revert LoanEngine_ZeroAmount();

        LoanPosition storage pos = positions[msg.sender];
        if (amount > pos.principalAmount) revert LoanEngine_RepayExceedsPrincipal();

        treasuryVault.pullFromBorrower(msg.sender, amount);

        pos.principalAmount -= amount;

        emit LoanRepaid(msg.sender, amount, pos.principalAmount);
    }

    /// @inheritdoc ILoanEngine
    function getTerms(address user) external view override returns (LoanTerms memory) {
        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(user);
        (uint256 ltvBps, uint256 rateBps) = _getTermsFromScore(profile.score);
        return LoanTerms({ltvBps: ltvBps, interestRateBps: rateBps});
    }

    /// @inheritdoc ILoanEngine
    function getPosition(address user) external view override returns (LoanPosition memory) {
        return positions[user];
    }

    function getCollateralBalance(address user) external view returns (uint256) {
        return collateralBalances[user];
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

        LoanPosition storage pos = positions[borrower];
        if (amount > pos.principalAmount) revert LoanEngine_RepayExceedsPrincipal();

        pos.principalAmount -= amount;

        emit LiquidationRepay(borrower, amount, pos.principalAmount);
    }

    function seizeCollateral(address borrower, address to, uint256 amount)
        external
        override
        onlyLiquidationManager
        nonReentrant
    {
        if (amount == 0) revert LoanEngine_ZeroAmount();
        if (collateralBalances[borrower] < amount) revert LoanEngine_InsufficientCollateral();

        collateralBalances[borrower] -= amount;
        collateral.safeTransfer(to, amount);

        emit CollateralSeized(borrower, to, amount);
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _getTermsFromScore(uint256 score)
        internal
        pure
        returns (uint256 ltvBps, uint256 interestRateBps)
    {
        if (score >= 851) return (8500, 500);   // 85% LTV, 5% APY
        if (score >= 700) return (7500, 700);    // 75% LTV, 7% APY
        if (score >= 400) return (6500, 1000);   // 65% LTV, 10% APY
        return (5000, 1500);                     // 50% LTV, 15% APY
    }
}
