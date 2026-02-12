// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {ICollateralManager} from "../src/interfaces/ICollateralManager.sol";

contract CollateralManagerTest is Test {
    CollateralManager public manager;
    address public owner;
    address public loanEngine;
    address public asset;

    function setUp() public {
        owner = makeAddr("owner");
        loanEngine = makeAddr("loanEngine");
        asset = makeAddr("asset");
        manager = new CollateralManager();
        manager.transferOwnership(owner);
    }

    function _validConfig() internal pure returns (ICollateralManager.CollateralConfig memory) {
        return ICollateralManager.CollateralConfig({
            enabled: true,
            ltvBpsCap: 7500,
            liquidationThresholdBpsCap: 8000,
            haircutBps: 9500,
            debtCeilingUSDC6: 1_000_000e6
        });
    }

    // -------------------------------------------------------------------------
    // Config — owner can set
    // -------------------------------------------------------------------------

    function test_Owner_CanSetConfig() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());

        ICollateralManager.CollateralConfig memory cfg = manager.getConfig(asset);
        assertTrue(cfg.enabled);
        assertEq(cfg.ltvBpsCap, 7500);
        assertEq(cfg.liquidationThresholdBpsCap, 8000);
        assertEq(cfg.haircutBps, 9500);
        assertEq(cfg.debtCeilingUSDC6, 1_000_000e6);
    }

    // -------------------------------------------------------------------------
    // Config — non-owner cannot set
    // -------------------------------------------------------------------------

    function test_NonOwner_CannotSetConfig() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        manager.setConfig(asset, _validConfig());
    }

    // -------------------------------------------------------------------------
    // Config — invalid BPS reverts
    // -------------------------------------------------------------------------

    function test_InvalidBps_HaircutOver10000_Reverts() public {
        ICollateralManager.CollateralConfig memory cfg = _validConfig();
        cfg.haircutBps = 10_001;

        vm.prank(owner);
        vm.expectRevert(CollateralManager.CollateralManager_InvalidBps.selector);
        manager.setConfig(asset, cfg);
    }

    function test_InvalidBps_LtvOver10000_Reverts() public {
        ICollateralManager.CollateralConfig memory cfg = _validConfig();
        cfg.ltvBpsCap = 10_001;

        vm.prank(owner);
        vm.expectRevert(CollateralManager.CollateralManager_InvalidBps.selector);
        manager.setConfig(asset, cfg);
    }

    function test_InvalidBps_LtvExceedsLiquidationThreshold_Reverts() public {
        ICollateralManager.CollateralConfig memory cfg = _validConfig();
        cfg.ltvBpsCap = 8500;
        cfg.liquidationThresholdBpsCap = 8000;

        vm.prank(owner);
        vm.expectRevert(CollateralManager.CollateralManager_InvalidBps.selector);
        manager.setConfig(asset, cfg);
    }

    // -------------------------------------------------------------------------
    // Config — disabled asset cannot accrue debt
    // -------------------------------------------------------------------------

    function test_DisabledAsset_IncreaseDebt_Reverts() public {
        ICollateralManager.CollateralConfig memory cfg = _validConfig();
        cfg.enabled = false;
        vm.prank(owner);
        manager.setConfig(asset, cfg);

        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(loanEngine);
        vm.expectRevert(CollateralManager.CollateralManager_AssetDisabled.selector);
        manager.increaseDebt(asset, 100e6);
    }

    // -------------------------------------------------------------------------
    // Debt ceiling — increase works under ceiling
    // -------------------------------------------------------------------------

    function test_IncreaseDebt_UnderCeiling_Succeeds() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(loanEngine);
        manager.increaseDebt(asset, 500_000e6);

        assertEq(manager.totalDebtUSDC6(asset), 500_000e6);

        vm.prank(loanEngine);
        manager.increaseDebt(asset, 300_000e6);

        assertEq(manager.totalDebtUSDC6(asset), 800_000e6);
    }

    // -------------------------------------------------------------------------
    // Debt ceiling — increase reverts above ceiling
    // -------------------------------------------------------------------------

    function test_IncreaseDebt_AboveCeiling_Reverts() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(loanEngine);
        manager.increaseDebt(asset, 900_000e6);

        vm.prank(loanEngine);
        vm.expectRevert(CollateralManager.CollateralManager_DebtCeilingExceeded.selector);
        manager.increaseDebt(asset, 200_000e6);
    }

    // -------------------------------------------------------------------------
    // Debt ceiling — decrease reduces total
    // -------------------------------------------------------------------------

    function test_DecreaseDebt_ReducesTotal() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(loanEngine);
        manager.increaseDebt(asset, 500_000e6);

        vm.prank(loanEngine);
        manager.decreaseDebt(asset, 200_000e6);

        assertEq(manager.totalDebtUSDC6(asset), 300_000e6);

        vm.prank(loanEngine);
        manager.decreaseDebt(asset, 300_000e6);

        assertEq(manager.totalDebtUSDC6(asset), 0);
    }

    // -------------------------------------------------------------------------
    // Debt ceiling — decrease reverts if amount > total
    // -------------------------------------------------------------------------

    function test_DecreaseDebt_AmountExceedsTotal_Reverts() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(loanEngine);
        manager.increaseDebt(asset, 100e6);

        vm.prank(loanEngine);
        vm.expectRevert(CollateralManager.CollateralManager_AmountExceedsTotal.selector);
        manager.decreaseDebt(asset, 200e6);
    }

    // -------------------------------------------------------------------------
    // Access control — only loanEngine can increase/decrease
    // -------------------------------------------------------------------------

    function test_OnlyLoanEngine_CanIncreaseDebt() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(makeAddr("rando"));
        vm.expectRevert(CollateralManager.CollateralManager_Unauthorized.selector);
        manager.increaseDebt(asset, 100e6);
    }

    function test_OnlyLoanEngine_CanDecreaseDebt() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);
        vm.prank(loanEngine);
        manager.increaseDebt(asset, 100e6);

        vm.prank(makeAddr("rando"));
        vm.expectRevert(CollateralManager.CollateralManager_Unauthorized.selector);
        manager.decreaseDebt(asset, 50e6);
    }

    // -------------------------------------------------------------------------
    // Access control — owner can setLoanEngine
    // -------------------------------------------------------------------------

    function test_Owner_CanSetLoanEngine() public {
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);
        assertEq(manager.loanEngine(), loanEngine);

        address newEngine = makeAddr("newEngine");
        vm.prank(owner);
        manager.setLoanEngine(newEngine);
        assertEq(manager.loanEngine(), newEngine);
    }

    function test_NonOwner_CannotSetLoanEngine() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        manager.setLoanEngine(loanEngine);
    }

    // -------------------------------------------------------------------------
    // Edge — setConfig with ceiling below current debt reverts
    // -------------------------------------------------------------------------

    function test_SetConfig_CeilingBelowCurrentDebt_Reverts() public {
        vm.prank(owner);
        manager.setConfig(asset, _validConfig());
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);
        vm.prank(loanEngine);
        manager.increaseDebt(asset, 500_000e6);

        ICollateralManager.CollateralConfig memory cfg = _validConfig();
        cfg.debtCeilingUSDC6 = 400_000e6;

        vm.prank(owner);
        vm.expectRevert(CollateralManager.CollateralManager_InvalidCeiling.selector);
        manager.setConfig(asset, cfg);
    }

    // -------------------------------------------------------------------------
    // Edge — zero address for asset and setLoanEngine
    // -------------------------------------------------------------------------

    function test_SetConfig_ZeroAsset_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(CollateralManager.CollateralManager_InvalidAddress.selector);
        manager.setConfig(address(0), _validConfig());
    }

    function test_SetLoanEngine_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(CollateralManager.CollateralManager_InvalidAddress.selector);
        manager.setLoanEngine(address(0));
    }

    // -------------------------------------------------------------------------
    // Edge — debt ceiling 0 means no ceiling (infinite) - actually, ceiling 0
    // -------------------------------------------------------------------------

    function test_DebtCeilingZero_NoCap() public {
        ICollateralManager.CollateralConfig memory cfg = _validConfig();
        cfg.debtCeilingUSDC6 = 0;
        vm.prank(owner);
        manager.setConfig(asset, cfg);
        vm.prank(owner);
        manager.setLoanEngine(loanEngine);

        vm.prank(loanEngine);
        manager.increaseDebt(asset, 10_000_000e6);
        assertEq(manager.totalDebtUSDC6(asset), 10_000_000e6);
    }
}
