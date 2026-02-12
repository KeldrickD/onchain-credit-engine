// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILoanEngine} from "./interfaces/ILoanEngine.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IPriceRouter} from "./interfaces/IPriceRouter.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LiquidationManager
/// @notice Keeper-style liquidation when position is undercollateralized.
///         Uses PriceRouter for price; supports Chainlink and Signed oracle sources.
contract LiquidationManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant USD8_TO_USDC6 = 100;

    ILoanEngine public immutable loanEngine;
    ICollateralManager public immutable collateralManager;
    IERC20 public immutable usdc;
    ITreasuryVault public immutable vault;
    IPriceRouter public immutable priceRouter;

    uint256 public constant liquidationThresholdBps = 8800;  // 88%
    uint256 public constant closeFactorBps = 5000;            // 50%
    uint256 public constant liquidationBonusBps = 800;         // 8%
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        uint256 repayAmount,
        uint256 collateralSeized
    );

    error LiquidationManager_HealthyPosition();
    error LiquidationManager_ZeroAmount();
    error LiquidationManager_ExceedsCloseFactor();
    error LiquidationManager_InsufficientCollateral();
    error LiquidationManager_NoPosition();
    error LiquidationManager_PriceStale();

    constructor(
        address _loanEngine,
        address _collateralManager,
        address _usdc,
        address _vault,
        address _priceRouter
    ) {
        loanEngine = ILoanEngine(_loanEngine);
        collateralManager = ICollateralManager(_collateralManager);
        usdc = IERC20(_usdc);
        vault = ITreasuryVault(_vault);
        priceRouter = IPriceRouter(_priceRouter);
    }

    function liquidate(
        address borrower,
        uint256 repayAmount,
        IPriceOracle.PricePayload calldata pricePayload,
        bytes calldata priceSignature
    ) external nonReentrant {
        if (repayAmount == 0) revert LiquidationManager_ZeroAmount();

        address asset = loanEngine.getPositionCollateralAsset(borrower);
        if (asset == address(0)) revert LiquidationManager_NoPosition();

        uint256 priceUSD8;
        if (priceRouter.getSource(asset) == IPriceRouter.Source.SIGNED) {
            priceUSD8 = priceRouter.updateSignedPriceAndGet(asset, pricePayload, priceSignature);
        } else {
            (uint256 p,, bool isStale) = priceRouter.getPriceUSD8(asset);
            priceUSD8 = p;
            if (isStale || priceUSD8 == 0) revert LiquidationManager_PriceStale();
        }

        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(borrower);
        uint256 collateralBal = loanEngine.getCollateralBalance(borrower, asset);

        uint256 collateralValueUSDC6 = _collateralValueUSDC6(asset, collateralBal, priceUSD8);
        uint256 effectiveLiqThresholdBps = _effectiveLiquidationThresholdBps(asset);
        uint256 healthFactor =
            (collateralValueUSDC6 * effectiveLiqThresholdBps * PRECISION) / (BPS * pos.principalAmount);

        if (healthFactor >= MIN_HEALTH_FACTOR) revert LiquidationManager_HealthyPosition();

        uint256 maxRepay = (pos.principalAmount * closeFactorBps) / BPS;
        if (repayAmount > maxRepay) revert LiquidationManager_ExceedsCloseFactor();

        vault.pullFromBorrower(msg.sender, repayAmount);
        loanEngine.liquidationRepay(borrower, repayAmount);

        uint256 collateralToSeize = _collateralAmountForRepay(asset, repayAmount, priceUSD8);
        if (collateralToSeize > collateralBal) revert LiquidationManager_InsufficientCollateral();

        loanEngine.seizeCollateral(borrower, msg.sender, collateralToSeize);

        emit Liquidated(borrower, msg.sender, repayAmount, collateralToSeize);
    }

    /// @notice Health factor given price in USD8
    function getHealthFactor(address borrower, uint256 priceUSD8)
        external
        view
        returns (uint256 healthFactor)
    {
        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(borrower);
        if (pos.principalAmount == 0) return type(uint256).max;

        address asset = pos.collateralAsset;
        uint256 collateralBal = loanEngine.getCollateralBalance(borrower, asset);
        uint256 collateralValueUSDC6 = _collateralValueUSDC6(asset, collateralBal, priceUSD8);
        uint256 effectiveLiqThresholdBps = _effectiveLiquidationThresholdBps(asset);

        return (collateralValueUSDC6 * effectiveLiqThresholdBps * PRECISION) / (BPS * pos.principalAmount);
    }

    function _effectiveLiquidationThresholdBps(address asset) internal view returns (uint256) {
        ICollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(asset);
        if (cfg.liquidationThresholdBpsCap == 0) return liquidationThresholdBps;
        return liquidationThresholdBps < cfg.liquidationThresholdBpsCap
            ? liquidationThresholdBps
            : cfg.liquidationThresholdBpsCap;
    }

    function _collateralValueUSDC6(address asset, uint256 amount, uint256 priceUSD8)
        internal
        view
        returns (uint256)
    {
        if (amount == 0 || priceUSD8 == 0) return 0;
        uint8 dec = IERC20Metadata(asset).decimals();
        uint256 valueUSD8 = (amount * priceUSD8) / (10 ** dec);
        return valueUSD8 / USD8_TO_USDC6;
    }

    function _collateralAmountForRepay(address asset, uint256 repayUSDC6, uint256 priceUSD8)
        internal
        view
        returns (uint256)
    {
        if (priceUSD8 == 0) return 0;
        uint8 dec = IERC20Metadata(asset).decimals();
        uint256 base = (repayUSDC6 * USD8_TO_USDC6 * (10 ** dec)) / priceUSD8;
        return (base * (BPS + liquidationBonusBps)) / BPS;
    }
}
