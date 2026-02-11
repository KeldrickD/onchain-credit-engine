// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILoanEngine} from "./interfaces/ILoanEngine.sol";
import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LiquidationManager
/// @notice Keeper-style liquidation when position is undercollateralized
contract LiquidationManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant COLLATERAL_DECIMALS = 1e18;

    ILoanEngine public immutable loanEngine;
    IERC20 public immutable collateral;
    IERC20 public immutable usdc;
    ITreasuryVault public immutable vault;
    IPriceOracle public immutable priceOracle;

    uint256 public constant liquidationThresholdBps = 8800;  // 88%
    uint256 public constant closeFactorBps = 5000;            // 50%
    uint256 public constant liquidationBonusBps = 800;        // 8%
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

    constructor(
        address _loanEngine,
        address _collateral,
        address _usdc,
        address _vault,
        address _priceOracle
    ) {
        loanEngine = ILoanEngine(_loanEngine);
        collateral = IERC20(_collateral);
        usdc = IERC20(_usdc);
        vault = ITreasuryVault(_vault);
        priceOracle = IPriceOracle(_priceOracle);
    }

    function liquidate(
        address borrower,
        uint256 repayAmount,
        IPriceOracle.PricePayload calldata pricePayload,
        bytes calldata priceSignature
    ) external nonReentrant {
        if (repayAmount == 0) revert LiquidationManager_ZeroAmount();

        priceOracle.verifyPricePayload(pricePayload, priceSignature);

        (uint256 price,) = priceOracle.getPrice(pricePayload.asset);
        require(price > 0, "LiquidationManager: no price");

        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(borrower);
        uint256 collateralBal = loanEngine.getCollateralBalance(borrower);

        uint256 collateralValueUSDC = (collateralBal * price) / COLLATERAL_DECIMALS;
        uint256 healthFactor =
            (collateralValueUSDC * liquidationThresholdBps * PRECISION) / (BPS * pos.principalAmount);

        if (healthFactor >= MIN_HEALTH_FACTOR) revert LiquidationManager_HealthyPosition();

        uint256 maxRepay = (pos.principalAmount * closeFactorBps) / BPS;
        if (repayAmount > maxRepay) revert LiquidationManager_ExceedsCloseFactor();

        vault.pullFromBorrower(msg.sender, repayAmount);
        loanEngine.liquidationRepay(borrower, repayAmount);

        uint256 collateralToSeize =
            (repayAmount * COLLATERAL_DECIMALS * (BPS + liquidationBonusBps)) / (price * BPS);

        if (collateralToSeize > collateralBal) revert LiquidationManager_InsufficientCollateral();

        loanEngine.seizeCollateral(borrower, msg.sender, collateralToSeize);

        emit Liquidated(borrower, msg.sender, repayAmount, collateralToSeize);
    }

    function getHealthFactor(address borrower, uint256 price)
        external
        view
        returns (uint256 healthFactor)
    {
        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(borrower);
        if (pos.principalAmount == 0) return type(uint256).max;

        uint256 collateralBal = loanEngine.getCollateralBalance(borrower);
        uint256 collateralValueUSDC = (collateralBal * price) / COLLATERAL_DECIMALS;

        return (collateralValueUSDC * liquidationThresholdBps * PRECISION) / (BPS * pos.principalAmount);
    }
}
