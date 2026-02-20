// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {LoanEngine} from "../src/LoanEngine.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {PriceRouter} from "../src/PriceRouter.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {SignedPriceOracle} from "../src/SignedPriceOracle.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockCollateral} from "./mocks/MockCollateral.sol";
import {MockERC20WithCallback} from "./mocks/MockERC20WithCallback.sol";
import {ReentrancyLiquidator} from "./mocks/ReentrancyLiquidator.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IPriceRouter} from "../src/interfaces/IPriceRouter.sol";
import {ICollateralManager} from "../src/interfaces/ICollateralManager.sol";

contract LiquidationManagerTest is Test {
    LiquidationManager public liqManager;
    LoanEngine public engine;
    CreditRegistry public creditRegistry;
    RiskOracle public riskOracle;
    TreasuryVault public vault;
    PriceRouter public priceRouter;
    SignedPriceOracle public signedOracle;
    CollateralManager public collateralManager;
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
    uint256 public constant PRICE_1_0_USD8 = 1e8;
    uint256 public constant PRICE_0_5_USD8 = 0.5e8;

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
        signedOracle = new SignedPriceOracle(priceSigner);
        priceRouter = new PriceRouter();
        priceRouter.transferOwnership(owner);
        collateralManager = new CollateralManager();
        collateralManager.transferOwnership(owner);

        engine = new LoanEngine(
            address(creditRegistry),
            address(vault),
            address(usdc),
            address(priceRouter),
            address(collateralManager)
        );

        liqManager = new LiquidationManager(
            address(engine),
            address(collateralManager),
            address(usdc),
            address(vault),
            address(priceRouter)
        );

        vm.prank(owner);
        vault.setLoanEngine(address(engine));
        vm.prank(owner);
        vault.setLiquidationManager(address(liqManager));
        engine.transferOwnership(owner);
        vm.prank(owner);
        engine.setLiquidationManager(address(liqManager));
        vm.prank(owner);
        collateralManager.setLoanEngine(address(engine));

        _setupCollateralWithSignedOracle();
        _openLoan();
    }

    function _setupCollateralWithSignedOracle() internal {
        vm.prank(owner);
        priceRouter.setSignedOracle(address(collateral), address(signedOracle));
        vm.prank(owner);
        priceRouter.setSource(address(collateral), IPriceRouter.Source.SIGNED);
        vm.prank(owner);
        collateralManager.setConfig(
            address(collateral),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 8000,
                liquidationThresholdBpsCap: 8800,
                haircutBps: 10_000,
                debtCeilingUSDC6: 500_000e6
            })
        );
    }

    function _openLoan() internal {
        IPriceOracle.PricePayload memory pricePayload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        signedOracle.verifyPricePayload(pricePayload, _signPricePayload(pricePayload));

        vm.startPrank(borrower);
        collateral.approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(address(collateral), COLLATERAL_AMOUNT);
        IRiskOracle.RiskPayload memory payload = IRiskOracle.RiskPayload({
            user: borrower,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: riskOracle.nextNonce(borrower)
        });
        bytes memory sig = _signRiskPayload(payload);
        engine.openLoan(address(collateral), BORROW_AMOUNT, payload, sig);
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

    function _makePricePayload(uint256 priceUSDC6)
        internal
        view
        returns (IPriceOracle.PricePayload memory)
    {
        return
            IPriceOracle.PricePayload({
                asset: address(collateral),
                price: priceUSDC6,
                timestamp: block.timestamp,
                nonce: signedOracle.nextNonce(address(collateral))
            });
    }

    function _signPricePayload(IPriceOracle.PricePayload memory payload)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = signedOracle.getPricePayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRICE_ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_HealthyPosition_CannotBeLiquidated() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(1e8);
        bytes memory sig = _signPricePayload(payload);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 10e6);
        vm.expectRevert(LiquidationManager.LiquidationManager_HealthyPosition.selector);
        liqManager.liquidate(borrower, 10e6, payload, sig);
        vm.stopPrank();
    }

    function test_PriceDrop_LiquidationSucceeds() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(0.5e8);
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
        IPriceOracle.PricePayload memory payload = _makePricePayload(0.5e8);
        bytes memory sig = _signPricePayload(payload);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 40e6);
        vm.expectRevert(LiquidationManager.LiquidationManager_ExceedsCloseFactor.selector);
        liqManager.liquidate(borrower, 40e6, payload, sig);
        vm.stopPrank();
    }

    function test_LiquidationBonusPaid() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(0.5e8);
        bytes memory sig = _signPricePayload(payload);

        uint256 repayAmount = 37.5e6;
        uint256 priceUSD8 = 0.5e8;
        uint256 baseCollateral = (repayAmount * 1e20) / priceUSD8;
        uint256 withBonus = (baseCollateral * (10000 + 800)) / 10000;

        vm.startPrank(liquidator);
        usdc.approve(address(vault), repayAmount);
        liqManager.liquidate(borrower, repayAmount, payload, sig);
        vm.stopPrank();

        assertEq(collateral.balanceOf(liquidator), withBonus);
    }

    function test_PricePayloadReplayFails() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(0.5e8);
        bytes memory sig = _signPricePayload(payload);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 75e6);
        liqManager.liquidate(borrower, 37.5e6, payload, sig);
        vm.expectRevert();
        liqManager.liquidate(borrower, 37.5e6, payload, sig);
        vm.stopPrank();
    }

    function test_LiquidatorMustApproveVault() public {
        IPriceOracle.PricePayload memory payload = _makePricePayload(0.5e8);
        bytes memory sig = _signPricePayload(payload);

        vm.prank(liquidator);
        vm.expectRevert();
        liqManager.liquidate(borrower, 37.5e6, payload, sig);
    }

    function test_ReentrancyViaMaliciousCollateral_Blocked() public {
        MockERC20WithCallback maliciousColl = new MockERC20WithCallback();
        maliciousColl.mint(borrower, 1000e18);

        signedOracle = new SignedPriceOracle(priceSigner);
        priceRouter = new PriceRouter();
        priceRouter.transferOwnership(owner);
        collateralManager = new CollateralManager();
        collateralManager.transferOwnership(owner);

        vm.startPrank(owner);
        priceRouter.setSignedOracle(address(maliciousColl), address(signedOracle));
        priceRouter.setSource(address(maliciousColl), IPriceRouter.Source.SIGNED);
        collateralManager.setConfig(
            address(maliciousColl),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 8000,
                liquidationThresholdBpsCap: 8800,
                haircutBps: 10_000,
                debtCeilingUSDC6: 500_000e6
            })
        );

        LoanEngine engineMal = new LoanEngine(
            address(creditRegistry),
            address(vault),
            address(usdc),
            address(priceRouter),
            address(collateralManager)
        );
        LiquidationManager liqMal = new LiquidationManager(
            address(engineMal),
            address(collateralManager),
            address(usdc),
            address(vault),
            address(priceRouter)
        );
        engineMal.setLiquidationManager(address(liqMal));
        vault.setLoanEngine(address(engineMal));
        vault.setLiquidationManager(address(liqMal));
        collateralManager.setLoanEngine(address(engineMal));
        vm.stopPrank();

        ReentrancyLiquidator attacker = new ReentrancyLiquidator(
            address(liqMal),
            address(usdc),
            address(vault)
        );
        usdc.mint(address(attacker), 50e6);
        maliciousColl.setCallbackTarget(address(attacker));

        IPriceOracle.PricePayload memory pricePayload = IPriceOracle.PricePayload({
            asset: address(maliciousColl),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(maliciousColl))
        });
        signedOracle.verifyPricePayload(pricePayload, _signPricePayloadForOracle(pricePayload, signedOracle));

        vm.startPrank(borrower);
        maliciousColl.approve(address(engineMal), 100e18);
        engineMal.depositCollateral(address(maliciousColl), 100e18);
        IRiskOracle.RiskPayload memory rp = IRiskOracle.RiskPayload({
            user: borrower,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: riskOracle.nextNonce(borrower)
        });
        engineMal.openLoan(address(maliciousColl), 75e6, rp, _signRiskPayload(rp));
        vm.stopPrank();

        attacker.setBorrower(borrower);
        IPriceOracle.PricePayload memory pp = IPriceOracle.PricePayload({
            asset: address(maliciousColl),
            price: 0.5e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(maliciousColl))
        }); // Drop price for liquidation
        bytes memory sig = _signPricePayloadForOracle(pp, signedOracle);
        vm.expectRevert();
        attacker.liquidate(37.5e6, pp, sig);
    }

    function _signPricePayloadForOracle(IPriceOracle.PricePayload memory payload, SignedPriceOracle oracle)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = oracle.getPricePayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRICE_ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_OnlyLiquidationManagerCanCallSeizeCollateral() public {
        vm.prank(liquidator);
        vm.expectRevert(LoanEngine.LoanEngine_OnlyLiquidationManager.selector);
        engine.seizeCollateral(borrower, liquidator, 10e18);
    }

    function test_Liquidation_UsesCappedThreshold() public {
        address borrower2 = makeAddr("borrower2");
        collateral.mint(borrower2, 1000e18);

        vm.prank(owner);
        collateralManager.setConfig(
            address(collateral),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 8000,
                liquidationThresholdBpsCap: 8300,
                haircutBps: 10_000,
                debtCeilingUSDC6: 500_000e6
            })
        );

        IPriceOracle.PricePayload memory pricePayload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        signedOracle.verifyPricePayload(pricePayload, _signPricePayloadForOracle(pricePayload, signedOracle));

        vm.startPrank(borrower2);
        collateral.approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(address(collateral), COLLATERAL_AMOUNT);
        IRiskOracle.RiskPayload memory rp = IRiskOracle.RiskPayload({
            user: borrower2,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: riskOracle.nextNonce(borrower2)
        });
        engine.openLoan(address(collateral), 75e6, rp, _signRiskPayload(rp));
        vm.stopPrank();

        IPriceOracle.PricePayload memory dropPayload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 0.90e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        bytes memory sig = _signPricePayloadForOracle(dropPayload, signedOracle);

        uint256 hfAt90 = liqManager.getHealthFactor(borrower2, 0.90e8);
        assertLt(hfAt90, 1e18);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), 37.5e6);
        liqManager.liquidate(borrower2, 37.5e6, dropPayload, sig);
        vm.stopPrank();

        assertEq(engine.getPosition(borrower2).principalAmount, 37.5e6);
    }

    function test_GetHealthFactor() public view {
        uint256 hf = liqManager.getHealthFactor(borrower, PRICE_1_0_USD8);
        assertGt(hf, 1e18);

        uint256 hfLow = liqManager.getHealthFactor(borrower, PRICE_0_5_USD8);
        assertLt(hfLow, 1e18);
    }
}
