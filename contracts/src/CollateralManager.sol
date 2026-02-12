// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CollateralManager
/// @notice Single source of truth for per-asset risk parameters: LTV caps, haircuts, debt ceilings.
///         Used by LoanEngine (max borrow, eligibility) and LiquidationManager (threshold caps).
contract CollateralManager is ICollateralManager, Ownable {
    mapping(address => CollateralConfig) private configs;
    mapping(address => uint128) private _totalDebt;
    address public loanEngine;

    event ConfigSet(
        address indexed asset,
        bool enabled,
        uint16 ltvBpsCap,
        uint16 liquidationThresholdBpsCap,
        uint16 haircutBps,
        uint128 debtCeilingUSDC6
    );
    event LoanEngineSet(address indexed oldEngine, address indexed newEngine);
    event DebtIncreased(address indexed asset, uint128 amount, uint128 total);
    event DebtDecreased(address indexed asset, uint128 amount, uint128 total);

    error CollateralManager_Unauthorized();
    error CollateralManager_AssetDisabled();
    error CollateralManager_InvalidBps();
    error CollateralManager_DebtCeilingExceeded();
    error CollateralManager_InvalidCeiling();
    error CollateralManager_InvalidAddress();
    error CollateralManager_AmountExceedsTotal();

    modifier onlyLoanEngine() {
        if (msg.sender != loanEngine) revert CollateralManager_Unauthorized();
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc ICollateralManager
    function setConfig(address asset, CollateralConfig calldata cfg) external onlyOwner {
        if (asset == address(0)) revert CollateralManager_InvalidAddress();
        if (cfg.haircutBps > 10_000) revert CollateralManager_InvalidBps();
        if (cfg.ltvBpsCap > 10_000 || cfg.liquidationThresholdBpsCap > 10_000) {
            revert CollateralManager_InvalidBps();
        }
        if (cfg.ltvBpsCap > cfg.liquidationThresholdBpsCap) revert CollateralManager_InvalidBps();
        if (cfg.debtCeilingUSDC6 > 0 && _totalDebt[asset] > cfg.debtCeilingUSDC6) {
            revert CollateralManager_InvalidCeiling();
        }

        configs[asset] = cfg;
        emit ConfigSet(
            asset,
            cfg.enabled,
            cfg.ltvBpsCap,
            cfg.liquidationThresholdBpsCap,
            cfg.haircutBps,
            cfg.debtCeilingUSDC6
        );
    }

    /// @notice Set the LoanEngine address (only caller of increaseDebt/decreaseDebt)
    function setLoanEngine(address engine) external onlyOwner {
        if (engine == address(0)) revert CollateralManager_InvalidAddress();
        address old = loanEngine;
        loanEngine = engine;
        emit LoanEngineSet(old, engine);
    }

    /// @inheritdoc ICollateralManager
    function getConfig(address asset) external view override returns (CollateralConfig memory) {
        return configs[asset];
    }

    /// @inheritdoc ICollateralManager
    function totalDebtUSDC6(address asset) external view override returns (uint128) {
        return _totalDebt[asset];
    }

    /// @inheritdoc ICollateralManager
    function increaseDebt(address asset, uint128 amountUSDC6) external override onlyLoanEngine {
        CollateralConfig memory cfg = configs[asset];
        if (!cfg.enabled) revert CollateralManager_AssetDisabled();

        uint128 ceiling = cfg.debtCeilingUSDC6;
        uint128 current = _totalDebt[asset];
        uint128 newTotal = current + amountUSDC6;
        if (ceiling > 0 && newTotal > ceiling) revert CollateralManager_DebtCeilingExceeded();

        _totalDebt[asset] = newTotal;
        emit DebtIncreased(asset, amountUSDC6, newTotal);
    }

    /// @inheritdoc ICollateralManager
    function decreaseDebt(address asset, uint128 amountUSDC6) external override onlyLoanEngine {
        uint128 current = _totalDebt[asset];
        if (amountUSDC6 > current) revert CollateralManager_AmountExceedsTotal();

        uint128 newTotal = current - amountUSDC6;
        _totalDebt[asset] = newTotal;
        emit DebtDecreased(asset, amountUSDC6, newTotal);
    }
}
