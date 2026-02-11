// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {LoanEngine} from "../src/LoanEngine.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {SignedPriceOracle} from "../src/SignedPriceOracle.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockCollateral} from "./mocks/MockCollateral.sol";
import {MockERC20WithCallback} from "./mocks/MockERC20WithCallback.sol";
import {ReentrancyLiquidator} from "./mocks/ReentrancyLiquidator.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

contract LiquidationManagerTest is Test {
    LiquidationManager public liqManager;
    LoanEngine public engine;
    CreditRegistry public creditRegistry;
    RiskOracle public riskOracle;
    TreasuryVault public vault;
    SignedPriceOracle public priceOracle;
    MockUSDC public usdc;
    MockCollateral public collateral;

    uint256 public constant ORACLE_PRIVATE_KEY = 0xA11CE;
    uint256 public constant PRICE_ORACLE_PRIVATE_KEY = 0xB0B7;
    address public owner;
    address public oracleSigner;
    address public priceSigner;
    address public borrower;
    address public liquidator;

    uint256 public constant VAULT_LIQUIDITY = 1_000_000e6;
    uint256 public constant COLLATERAL_AMOUNT = 100e18;
    uint256 public constant BORROW_AMOUNT = 75e6;
    uint256 public constant PRICE_1_0 = 1_000_000;
    uint256 public constant PRICE_0_5 = 500_000;

    function setUp() public {
        vm.warp(1000);

        owner = makeAddr("owner");
        oracleSigner = vm.addr(ORACLE_PRIVATE_KEY);
        priceSigner = vm.addr(PRICE_ORACLE_PRIVATE_KEY);
        borrower = makeAddr("borrower");
        liquidator = makeAddr("liquidator");

        usdc = new MockUSDC();
        collateral = new MockCollateral();
        usdc.mint(owner, VAULT_LIQUIDITY);
        collateral.mint(borrower, 1000e18);
        usdc.mint(liquidator, 100_000e6);

        vm.startPrank(owner);
        vault = new TreasuryVault(address(usdc), owner);
        usdc.transfer(address(vault), VAULT_LIQUIDITY);
        vm.stopPrank();

        riskOracle = new RiskOracle(oracleSigner);
        creditRegistry = new CreditRegistry(address(riskOracle));
        priceOracle = new SignedPriceOracle(priceSigner);

        engine = new LoanEngine(
            address(creditRegistry),
            address(vault),
            address(usdc),
            address(collateral)
        );

        liqManager = new LiquidationManager(
            address(engine),
            address(collateral),
            address(usdc),
            address(vault),
            address(priceOracle)
        );

        vm.prank(owner);
        vault.setLoanEngine(address(engine));
        vm.prank(owner);
        vault.setLiquidationManager(address(liqManager));
        engine.setLiquidationManager(address(liqManager));

        _openLoan();
    }

    function _openLoan() internal {
        vm.startPrank(borrower);
        collateral.approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(COLLATERAL_AMOUNT);
        IRiskOracle.RiskPayload memory payload = IRiskOracle.RiskPayload({
            user: borrower,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: 1
        });
        bytes memory sig = _signRiskPayload(payload);
        engine.openLoan(BORROW_AMOUNT, payload, sig);
        vm.stopPrank();
    }

    function _signRiskPayload(IRiskOracle.RiskPayload memory payload)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = riskOracle.getPayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _makePricePayload(uint256 price, uint256 nonce)
        internal
        view
        returns (IPriceOracle.PricePayload memory)
    {
        return _makePricePayloadForAsset(address(collateral), price, nonce);
    }

    function _makePricePayloadForAsset(address asset, uint256 price, uint256 nonce)
        internal
        view
        returns (IPriceOracle.PricePayload memory)
    {
        return
            IPriceOracle.PricePayload({
                asset: asset,
                price: price,
                timestamp: block.timestamp,
                nonce: nonce
            });
    }

    function _signPricePayload(IPriceOracle.PricePayload memory payload)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = priceOracle.getPricePayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRICE_ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_HealthyPosition_CannotBeLiquidated() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(PRICE_1_0, 1);
        bytes memory sig = _signPricePayload(payload);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 10e6);
        vm.expectRevert(LiquidationManager.LiquidationManager_HealthyPosition.selector);
        liqManager.liquidate(borrower, 10e6, payload, sig);
        vm.stopPrank();
    }

    function test_PriceDrop_LiquidationSucceeds() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(PRICE_0_5, 1);
        bytes memory sig = _signPricePayload(payload);

        uint256 liqBalBefore = collateral.balanceOf(liquidator);
        uint256 repayAmount = 37.5e6;

        vm.startPrank(liquidator);
        usdc.approve(address(vault), repayAmount);
        liqManager.liquidate(borrower, repayAmount, payload, sig);
        vm.stopPrank();

        assertEq(engine.getPosition(borrower).principalAmount, BORROW_AMOUNT - repayAmount);
        assertGt(collateral.balanceOf(liquidator), liqBalBefore);
    }

    function test_CloseFactorEnforced() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(PRICE_0_5, 1);
        bytes memory sig = _signPricePayload(payload);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 40e6);
        vm.expectRevert(LiquidationManager.LiquidationManager_ExceedsCloseFactor.selector);
        liqManager.liquidate(borrower, 40e6, payload, sig);
        vm.stopPrank();
    }

    function test_LiquidationBonusPaid() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(PRICE_0_5, 1);
        bytes memory sig = _signPricePayload(payload);

        uint256 repayAmount = 37.5e6;
        uint256 baseCollateral = (repayAmount * 1e18) / PRICE_0_5;
        uint256 withBonus = (baseCollateral * (10000 + 800)) / 10000;

        vm.startPrank(liquidator);
        usdc.approve(address(vault), repayAmount);
        liqManager.liquidate(borrower, repayAmount, payload, sig);
        vm.stopPrank();

        assertEq(collateral.balanceOf(liquidator), withBonus);
    }

    function test_PricePayloadReplayFails() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(PRICE_0_5, 1);
        bytes memory sig = _signPricePayload(payload);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 75e6);
        liqManager.liquidate(borrower, 37.5e6, payload, sig);
        vm.expectRevert();
        liqManager.liquidate(borrower, 37.5e6, payload, sig);
        vm.stopPrank();
    }

    function test_LiquidatorMustApproveVault() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(PRICE_0_5, 1);
        bytes memory sig = _signPricePayload(payload);

        vm.prank(liquidator);
        vm.expectRevert();
        liqManager.liquidate(borrower, 37.5e6, payload, sig);
    }

    function test_ReentrancyViaMaliciousCollateral_Blocked() public {
        MockERC20WithCallback maliciousColl = new MockERC20WithCallback();
        maliciousColl.mint(borrower, 1000e18);

        vm.startPrank(owner);
        LoanEngine engineMal = new LoanEngine(
            address(creditRegistry),
            address(vault),
            address(usdc),
            address(maliciousColl)
        );
        LiquidationManager liqMal = new LiquidationManager(
            address(engineMal),
            address(maliciousColl),
            address(usdc),
            address(vault),
            address(priceOracle)
        );
        engineMal.setLiquidationManager(address(liqMal));
        vault.setLoanEngine(address(engineMal));
        vault.setLiquidationManager(address(liqMal));
        vm.stopPrank();

        ReentrancyLiquidator attacker = new ReentrancyLiquidator(
            address(liqMal),
            address(usdc),
            address(vault)
        );
        usdc.mint(address(attacker), 50e6);
        maliciousColl.setCallbackTarget(address(attacker));

        vm.startPrank(borrower);
        maliciousColl.approve(address(engineMal), 100e18);
        engineMal.depositCollateral(100e18);
        IRiskOracle.RiskPayload memory rp = IRiskOracle.RiskPayload({
            user: borrower,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: 100
        });
        engineMal.openLoan(75e6, rp, _signRiskPayload(rp));
        vm.stopPrank();

        priceOracle.verifyPricePayload(
            _makePricePayloadForAsset(address(maliciousColl), PRICE_0_5, 50),
            _signPricePayload(_makePricePayloadForAsset(address(maliciousColl), PRICE_0_5, 50))
        );

        attacker.setBorrower(borrower);
        IPriceOracle.PricePayload memory pp = _makePricePayloadForAsset(address(maliciousColl), PRICE_0_5, 51);
        bytes memory sig = _signPricePayload(pp);
        vm.expectRevert();
        attacker.liquidate(37.5e6, pp, sig);
    }

    function test_OnlyLiquidationManagerCanCallSeizeCollateral() public {
        vm.prank(liquidator);
        vm.expectRevert(LoanEngine.LoanEngine_OnlyLiquidationManager.selector);
        engine.seizeCollateral(borrower, liquidator, 10e18);
    }

    function test_GetHealthFactor() public view {
        uint256 hf = liqManager.getHealthFactor(borrower, PRICE_1_0);
        assertGt(hf, 1e18);

        uint256 hfLow = liqManager.getHealthFactor(borrower, PRICE_0_5);
        assertLt(hfLow, 1e18);
    }
}
