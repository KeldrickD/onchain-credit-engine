// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LoanEngine} from "../src/LoanEngine.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockCollateral} from "./mocks/MockCollateral.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {ILoanEngine} from "../src/interfaces/ILoanEngine.sol";

contract LoanEngineTest is Test {
    LoanEngine public engine;
    CreditRegistry public creditRegistry;
    RiskOracle public riskOracle;
    TreasuryVault public vault;
    MockUSDC public usdc;
    MockCollateral public collateral;

    uint256 public constant ORACLE_PRIVATE_KEY = 0xA11CE;
    address public owner;
    address public oracleSigner;
    address public borrower;

    uint256 public constant VAULT_LIQUIDITY = 1_000_000e6;
    uint256 public constant COLLATERAL_AMOUNT = 100e18; // 100 tokens (18 decimals)

    function setUp() public {
        vm.warp(1000);

        owner = makeAddr("owner");
        oracleSigner = vm.addr(ORACLE_PRIVATE_KEY);
        borrower = makeAddr("borrower");

        usdc = new MockUSDC();
        collateral = new MockCollateral();

        usdc.mint(owner, VAULT_LIQUIDITY);
        collateral.mint(borrower, 1000e18);

        vm.startPrank(owner);
        vault = new TreasuryVault(address(usdc), owner);
        usdc.transfer(address(vault), VAULT_LIQUIDITY);
        vm.stopPrank();

        riskOracle = new RiskOracle(oracleSigner);
        creditRegistry = new CreditRegistry(address(riskOracle));
        engine = new LoanEngine(
            address(creditRegistry),
            address(vault),
            address(usdc),
            address(collateral)
        );

        vm.prank(owner);
        vault.setLoanEngine(address(engine));
    }

    function _makePayload(uint256 score, uint256 nonce)
        internal
        view
        returns (IRiskOracle.RiskPayload memory)
    {
        return
            IRiskOracle.RiskPayload({
                user: borrower,
                score: score,
                riskTier: score >= 700 ? 1 : (score >= 400 ? 2 : 3),
                timestamp: block.timestamp,
                nonce: nonce
            });
    }

    function _signPayload(IRiskOracle.RiskPayload memory payload) internal view returns (bytes memory) {
        bytes32 digest = riskOracle.getPayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _depositCollateralAndOpenLoan(uint256 collAmount, uint256 score, uint256 borrowAmount)
        internal
    {
        vm.startPrank(borrower);
        collateral.approve(address(engine), collAmount);
        engine.depositCollateral(collAmount);

        IRiskOracle.RiskPayload memory payload = _makePayload(score, 1);
        bytes memory sig = _signPayload(payload);
        engine.openLoan(borrowAmount, payload, sig);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // depositCollateral
    // -------------------------------------------------------------------------

    function test_DepositCollateral_UpdatesBalanceAndTransfers() public {
        vm.startPrank(borrower);
        collateral.approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(COLLATERAL_AMOUNT);
        vm.stopPrank();

        assertEq(engine.getCollateralBalance(borrower), COLLATERAL_AMOUNT);
        assertEq(collateral.balanceOf(address(engine)), COLLATERAL_AMOUNT);
        assertEq(collateral.balanceOf(borrower), 1000e18 - COLLATERAL_AMOUNT);
    }

    function test_DepositCollateral_Zero_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_ZeroAmount.selector);
        engine.depositCollateral(0);
    }

    // -------------------------------------------------------------------------
    // openLoan
    // -------------------------------------------------------------------------

    function test_OpenLoan_SucceedsWithValidPayloadAndEnoughCollateral() public {
        _depositCollateralAndOpenLoan(100e18, 750, 75e6); // 75% LTV, max 75 USDC

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertEq(pos.collateralAmount, 100e18);
        assertEq(pos.principalAmount, 75e6);
        assertEq(pos.ltvBps, 7500);
        assertEq(pos.interestRateBps, 700);
        assertEq(usdc.balanceOf(borrower), 75e6);
    }

    function test_OpenLoan_FailsWithoutCollateral() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_BorrowExceedsMax.selector);
        engine.openLoan(1e6, payload, sig);
    }

    function test_OpenLoan_FailsIfBorrowExceedsMax() public {
        vm.startPrank(borrower);
        collateral.approve(address(engine), 100e18);
        engine.depositCollateral(100e18);
        vm.stopPrank();

        // 750 score = 75% LTV, max 75 USDC
        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_BorrowExceedsMax.selector);
        engine.openLoan(76e6, payload, sig);
    }

    function test_OpenLoan_ConsumesOracleNonce_ReplayFails() public {
        _depositCollateralAndOpenLoan(100e18, 750, 50e6);

        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert();
        engine.openLoan(10e6, payload, sig);
    }

    function test_OpenLoan_FailsInsufficientVaultLiquidity() public {
        TreasuryVault emptyVault = new TreasuryVault(address(usdc), owner);
        vm.prank(owner);
        emptyVault.setLoanEngine(address(engine));

        LoanEngine engineEmptyVault = new LoanEngine(
            address(creditRegistry),
            address(emptyVault),
            address(usdc),
            address(collateral)
        );
        vm.prank(owner);
        emptyVault.setLoanEngine(address(engineEmptyVault));

        vm.startPrank(borrower);
        collateral.approve(address(engineEmptyVault), 100e18);
        engineEmptyVault.depositCollateral(100e18);

        IRiskOracle.RiskPayload memory payload = _makePayload(750, 99);
        bytes memory sig = _signPayload(payload);

        vm.expectRevert(LoanEngine.LoanEngine_InsufficientVaultLiquidity.selector);
        engineEmptyVault.openLoan(75e6, payload, sig);
        vm.stopPrank();
    }

    function test_GetTerms_ReturnsCorrectTieredTerms() public view {
        // Score 851-1000: LTV 85%, rate 500
        ILoanEngine.LoanTerms memory t1 = engine.getTerms(borrower);
        assertEq(t1.ltvBps, 5000);
        assertEq(t1.interestRateBps, 1500);

        // We haven't updated profile - getTerms uses current profile. With no profile, score is 0.
        // So we get tier 0: 50% LTV, 1500 bps. The getTerms reads creditRegistry.getCreditProfile.
        // A fresh profile has score 0, riskTier 0, etc. Actually CreditProfile is a struct - what
        // are default values? score=0, riskTier=0. So _getTermsFromScore(0) returns (5000, 1500).
        // Good - that matches.
    }

    function test_GetTerms_ScoreBands() public {
        vm.startPrank(borrower);
        IRiskOracle.RiskPayload memory p400 = _makePayload(400, 10);
        creditRegistry.updateCreditProfile(p400, _signPayload(p400));
        vm.stopPrank();

        ILoanEngine.LoanTerms memory t400 = engine.getTerms(borrower);
        assertEq(t400.ltvBps, 6500);
        assertEq(t400.interestRateBps, 1000);

        vm.startPrank(borrower);
        IRiskOracle.RiskPayload memory p700 = _makePayload(700, 11);
        creditRegistry.updateCreditProfile(p700, _signPayload(p700));
        vm.stopPrank();

        ILoanEngine.LoanTerms memory t700 = engine.getTerms(borrower);
        assertEq(t700.ltvBps, 7500);
        assertEq(t700.interestRateBps, 700);

        vm.startPrank(borrower);
        IRiskOracle.RiskPayload memory p900 = _makePayload(900, 12);
        creditRegistry.updateCreditProfile(p900, _signPayload(p900));
        vm.stopPrank();

        ILoanEngine.LoanTerms memory t900 = engine.getTerms(borrower);
        assertEq(t900.ltvBps, 8500);
        assertEq(t900.interestRateBps, 500);
    }

    // -------------------------------------------------------------------------
    // repay
    // -------------------------------------------------------------------------

    function test_Repay_ReducesPrincipal() public {
        _depositCollateralAndOpenLoan(100e18, 750, 75e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 50e6);
        engine.repay(50e6);
        vm.stopPrank();

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertEq(pos.principalAmount, 25e6);
    }

    function test_Repay_ExceedsPrincipal_Reverts() public {
        _depositCollateralAndOpenLoan(100e18, 750, 50e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 51e6);
        vm.expectRevert(LoanEngine.LoanEngine_RepayExceedsPrincipal.selector);
        engine.repay(51e6);
        vm.stopPrank();
    }

    function test_Repay_FullRepay_ZeroesPrincipal() public {
        _depositCollateralAndOpenLoan(100e18, 750, 50e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 50e6);
        engine.repay(50e6);
        vm.stopPrank();

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertEq(pos.principalAmount, 0);
    }

    // -------------------------------------------------------------------------
    // withdrawCollateral
    // -------------------------------------------------------------------------

    function test_WithdrawCollateral_BlockedIfViolatesLTV() public {
        _depositCollateralAndOpenLoan(100e18, 750, 75e6);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_WithdrawWouldViolateLTV.selector);
        engine.withdrawCollateral(50e18);
    }

    function test_WithdrawCollateral_AllowedAfterRepay() public {
        _depositCollateralAndOpenLoan(100e18, 750, 75e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 75e6);
        engine.repay(75e6);
        vm.stopPrank();

        uint256 balBefore = collateral.balanceOf(borrower);
        vm.prank(borrower);
        engine.withdrawCollateral(100e18);

        assertEq(engine.getCollateralBalance(borrower), 0);
        assertEq(collateral.balanceOf(borrower), balBefore + 100e18);
    }

    function test_WithdrawCollateral_PartialRepay_WithdrawUpToLTV() public {
        _depositCollateralAndOpenLoan(100e18, 750, 75e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 37.5e6);
        engine.repay(37.5e6);
        vm.stopPrank();

        // 37.5e6 principal, 75% LTV → min collateral = 37.5e6 * 1e12 * 10000 / 7500 = 50e18
        uint256 maxWithdraw = 50e18;
        vm.prank(borrower);
        engine.withdrawCollateral(maxWithdraw);

        assertEq(engine.getCollateralBalance(borrower), 50e18);
    }

    function test_OpenLoan_ActiveLoan_Reverts() public {
        _depositCollateralAndOpenLoan(100e18, 750, 50e6);

        IRiskOracle.RiskPayload memory payload = _makePayload(750, 2);
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_ActiveLoanExists.selector);
        engine.openLoan(10e6, payload, sig);
    }

    function test_OpenLoan_FailsIfPayloadUserMismatch() public {
        vm.startPrank(borrower);
        collateral.approve(address(engine), 100e18);
        engine.depositCollateral(100e18);
        vm.stopPrank();

        address otherUser = makeAddr("other");
        IRiskOracle.RiskPayload memory payload = IRiskOracle.RiskPayload({
            user: otherUser,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: 1
        });
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_InvalidPayloadUser.selector);
        engine.openLoan(75e6, payload, sig);
    }
}
