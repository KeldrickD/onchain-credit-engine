// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICollateralManager
/// @notice Single source of truth for per-asset risk parameters. Used by LoanEngine (max borrow)
///         and LiquidationManager (threshold caps).
interface ICollateralManager {
    struct CollateralConfig {
        bool enabled;
        uint16 ltvBpsCap;                   // max borrow LTV cap (overrides score curve)
        uint16 liquidationThresholdBpsCap; // max liquidation threshold cap
        uint16 haircutBps;                  // valuation haircut (e.g. 9000 = -10%, <= 10000)
        uint128 debtCeilingUSDC6;           // cap on total debt against this asset
    }

    function setConfig(address asset, CollateralConfig calldata cfg) external;

    function getConfig(address asset) external view returns (CollateralConfig memory);

    function totalDebtUSDC6(address asset) external view returns (uint128);

    function increaseDebt(address asset, uint128 amountUSDC6) external;

    function decreaseDebt(address asset, uint128 amountUSDC6) external;
}
