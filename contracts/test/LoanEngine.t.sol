// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LoanEngine} from "../src/LoanEngine.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {PriceRouter} from "../src/PriceRouter.sol";
import {SignedPriceOracle} from "../src/SignedPriceOracle.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockCollateral} from "./mocks/MockCollateral.sol";
import {MockWBTC} from "./mocks/MockWBTC.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {ILoanEngine} from "../src/interfaces/ILoanEngine.sol";
import {ICollateralManager} from "../src/interfaces/ICollateralManager.sol";
import {IPriceRouter} from "../src/interfaces/IPriceRouter.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LoanEngineTest is Test {
    LoanEngine public engine;
    CreditRegistry public creditRegistry;
    RiskOracle public riskOracle;
    TreasuryVault public vault;
    CollateralManager public collateralManager;
    PriceRouter public priceRouter;
    SignedPriceOracle public signedOracle;
    MockUSDC public usdc;
    MockCollateral public weth;
    MockWBTC public wbtc;
    MockChainlinkFeed public wethFeed;
    MockChainlinkFeed public wbtcFeed;

    uint256 public constant ORACLE_PRIVATE_KEY = 0xA11CE;
    uint256 public constant PRICE_ORACLE_PRIVATE_KEY = 0xB0B7;
    address public owner;
    address public oracleSigner;
    address public priceSigner;
    address public borrower;

    uint256 public constant VAULT_LIQUIDITY = 1_000_000e6;
    uint256 public constant COLLATERAL_AMOUNT = 100e18;

    function setUp() public {
        vm.warp(1000);

        owner = makeAddr("owner");
        oracleSigner = vm.addr(ORACLE_PRIVATE_KEY);
        priceSigner = vm.addr(PRICE_ORACLE_PRIVATE_KEY);
        borrower = makeAddr("borrower");

        usdc = new MockUSDC();
        weth = new MockCollateral();
        wbtc = new MockWBTC();
        wethFeed = new MockChainlinkFeed(1e8);      // $1
        wbtcFeed = new MockChainlinkFeed(50_000e8); // $50k

        usdc.mint(owner, VAULT_LIQUIDITY);
        weth.mint(borrower, 1000e18);
        wbtc.mint(borrower, 10e8);

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

        vm.prank(owner);
        vault.setLoanEngine(address(engine));
        vm.prank(owner);
        collateralManager.setLoanEngine(address(engine));

        _setupWethCollateral();
        _setupWbtcCollateral();
    }

    function _setupWethCollateral() internal {
        vm.prank(owner);
        priceRouter.setChainlinkFeed(address(weth), address(wethFeed));
        vm.prank(owner);
        priceRouter.setSource(address(weth), IPriceRouter.Source.CHAINLINK);
        vm.prank(owner);
        collateralManager.setConfig(
            address(weth),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 8000,
                liquidationThresholdBpsCap: 8800,
                haircutBps: 10_000,
                debtCeilingUSDC6: 500_000e6
            })
        );
    }

    function _setupWbtcCollateral() internal {
        vm.prank(owner);
        priceRouter.setChainlinkFeed(address(wbtc), address(wbtcFeed));
        vm.prank(owner);
        priceRouter.setSource(address(wbtc), IPriceRouter.Source.CHAINLINK);
        vm.prank(owner);
        collateralManager.setConfig(
            address(wbtc),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 7000,
                liquidationThresholdBpsCap: 8000,
                haircutBps: 9500,
                debtCeilingUSDC6: 1_000_000e6
            })
        );
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

    function _depositAndOpenLoan(address asset, uint256 collAmount, uint256 score, uint256 borrowAmount)
        internal
    {
        vm.startPrank(borrower);
        IERC20(asset).approve(address(engine), collAmount);
        engine.depositCollateral(asset, collAmount);
        IRiskOracle.RiskPayload memory payload = _makePayload(score, 1);
        bytes memory sig = _signPayload(payload);
        engine.openLoan(asset, borrowAmount, payload, sig);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Multi-asset deposit tracking
    // -------------------------------------------------------------------------

    function test_MultiAssetDeposit_TrackedIndependently() public {
        vm.startPrank(borrower);
        weth.approve(address(engine), 50e18);
        engine.depositCollateral(address(weth), 50e18);
        wbtc.approve(address(engine), 2e8);
        engine.depositCollateral(address(wbtc), 2e8);
        vm.stopPrank();

        assertEq(engine.getCollateralBalance(borrower, address(weth)), 50e18);
        assertEq(engine.getCollateralBalance(borrower, address(wbtc)), 2e8);
    }

    // -------------------------------------------------------------------------
    // depositCollateral
    // -------------------------------------------------------------------------

    function test_DepositCollateral_UpdatesBalanceAndTransfers() public {
        vm.startPrank(borrower);
        weth.approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(address(weth), COLLATERAL_AMOUNT);
        vm.stopPrank();

        assertEq(engine.getCollateralBalance(borrower, address(weth)), COLLATERAL_AMOUNT);
        assertEq(weth.balanceOf(address(engine)), COLLATERAL_AMOUNT);
        assertEq(weth.balanceOf(borrower), 1000e18 - COLLATERAL_AMOUNT);
    }

    function test_DepositCollateral_Zero_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_ZeroAmount.selector);
        engine.depositCollateral(address(weth), 0);
    }

    // -------------------------------------------------------------------------
    // openLoan — maxBorrow uses haircut + caps
    // -------------------------------------------------------------------------

    function test_MaxBorrow_UsesHaircutAndCap() public {
        // WBTC: haircut 9500 (5% reduction), ltvBpsCap 7000. Score 850 would give 85% LTV but cap forces 70%
        vm.startPrank(borrower);
        creditRegistry.updateCreditProfile(_makePayload(850, 1), _signPayload(_makePayload(850, 1)));
        wbtc.approve(address(engine), 1e8);
        engine.depositCollateral(address(wbtc), 1e8);
        vm.stopPrank();

        // 1 BTC @ $50k = $50k. After 5% haircut = $47.5k. 70% LTV = $33.25k max
        uint256 maxBorrow = engine.getMaxBorrow(borrower, address(wbtc));
        assertEq(maxBorrow, 33_250e6);

        vm.startPrank(borrower);
        engine.openLoan(address(wbtc), 33_250e6, _makePayload(850, 2), _signPayload(_makePayload(850, 2)));
        vm.stopPrank();
        assertEq(engine.getPosition(borrower).principalAmount, 33_250e6);
    }

    function test_OpenLoan_SucceedsWithValidPayload() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 75e6);

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertEq(pos.collateralAsset, address(weth));
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
        engine.openLoan(address(weth), 1e6, payload, sig);
    }

    function test_OpenLoan_FailsIfBorrowExceedsMax() public {
        vm.startPrank(borrower);
        weth.approve(address(engine), 100e18);
        engine.depositCollateral(address(weth), 100e18);
        vm.stopPrank();

        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_BorrowExceedsMax.selector);
        engine.openLoan(address(weth), 76e6, payload, sig);
    }

    function test_OpenLoan_ConsumesOracleNonce_ReplayFails() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);

        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        bytes memory sig = _signPayload(payload);

        vm.prank(borrower);
        vm.expectRevert();
        engine.openLoan(address(weth), 10e6, payload, sig);
    }

    function test_OpenLoan_FailsInsufficientVaultLiquidity() public {
        TreasuryVault emptyVault = new TreasuryVault(address(usdc), owner);

        LoanEngine engineEmpty = new LoanEngine(
            address(creditRegistry),
            address(emptyVault),
            address(usdc),
            address(priceRouter),
            address(collateralManager)
        );
        vm.prank(owner);
        emptyVault.setLoanEngine(address(engineEmpty));
        vm.prank(owner);
        collateralManager.setLoanEngine(address(engineEmpty));

        vm.startPrank(borrower);
        weth.approve(address(engineEmpty), 100e18);
        engineEmpty.depositCollateral(address(weth), 100e18);
        IRiskOracle.RiskPayload memory payload = _makePayload(750, 99);
        bytes memory sig = _signPayload(payload);
        vm.expectRevert(LoanEngine.LoanEngine_InsufficientVaultLiquidity.selector);
        engineEmpty.openLoan(address(weth), 75e6, payload, sig);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Debt ceiling enforced
    // -------------------------------------------------------------------------

    function test_DebtCeiling_Enforced() public {
        vm.prank(owner);
        collateralManager.setConfig(
            address(weth),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 8000,
                liquidationThresholdBpsCap: 8800,
                haircutBps: 10_000,
                debtCeilingUSDC6: 1_000e6
            })
        );

        weth.mint(borrower, 1500e18);
        vm.startPrank(borrower);
        weth.approve(address(engine), 1500e18);
        engine.depositCollateral(address(weth), 1500e18);
        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        engine.openLoan(address(weth), 900e6, payload, _signPayload(payload));

        address borrower2 = makeAddr("borrower2");
        weth.mint(borrower2, 500e18);
        vm.stopPrank();

        vm.startPrank(borrower2);
        weth.approve(address(engine), 300e18);
        engine.depositCollateral(address(weth), 300e18); // 300e6 value, 80% = 240e6 max
        IRiskOracle.RiskPayload memory p2 = IRiskOracle.RiskPayload({
            user: borrower2,
            score: 750,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: 200
        });
        bytes memory sig2 = _signPayload(p2);
        vm.expectRevert(CollateralManager.CollateralManager_DebtCeilingExceeded.selector);
        engine.openLoan(address(weth), 200e6, p2, sig2);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Repay decreases totalDebt
    // -------------------------------------------------------------------------

    function test_Repay_DecreasesTotalDebt() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);
        assertEq(collateralManager.totalDebtUSDC6(address(weth)), 50e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 30e6);
        engine.repay(30e6);
        vm.stopPrank();

        assertEq(collateralManager.totalDebtUSDC6(address(weth)), 20e6);
    }

    function test_Repay_ReducesPrincipal() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 75e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 50e6);
        engine.repay(50e6);
        vm.stopPrank();

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertEq(pos.principalAmount, 25e6);
    }

    function test_Repay_Overpay_ClampedToDebt() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 51e6);
        engine.repay(51e6); // Clamped to 50e6, full repay
        vm.stopPrank();

        assertEq(engine.getPosition(borrower).principalAmount, 0);
    }

    function test_Repay_FullRepay_ZeroesPrincipal() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 50e6);
        engine.repay(50e6);
        vm.stopPrank();

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertEq(pos.principalAmount, 0);
        assertEq(collateralManager.totalDebtUSDC6(address(weth)), 0);
    }

    // -------------------------------------------------------------------------
    // withdrawCollateral
    // -------------------------------------------------------------------------

    function test_WithdrawCollateral_BlockedIfViolatesLTV() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 75e6);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_WithdrawWouldViolateLTV.selector);
        engine.withdrawCollateral(address(weth), 50e18);
    }

    function test_WithdrawCollateral_AllowedAfterRepay() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 75e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 75e6);
        engine.repay(75e6);
        vm.stopPrank();

        uint256 balBefore = weth.balanceOf(borrower);
        vm.prank(borrower);
        engine.withdrawCollateral(address(weth), 100e18);

        assertEq(engine.getCollateralBalance(borrower, address(weth)), 0);
        assertEq(weth.balanceOf(borrower), balBefore + 100e18);
    }

    function test_WithdrawCollateral_PartialRepay_WithdrawUpToLTV() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 75e6);

        vm.startPrank(borrower);
        usdc.approve(address(vault), 37.5e6);
        engine.repay(37.5e6);
        vm.stopPrank();

        uint256 maxWithdraw = 50e18;
        vm.prank(borrower);
        engine.withdrawCollateral(address(weth), maxWithdraw);

        assertEq(engine.getCollateralBalance(borrower, address(weth)), 50e18);
    }

    function test_OpenLoan_ActiveLoan_Reverts() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);

        IRiskOracle.RiskPayload memory payload = _makePayload(750, 2);
        bytes memory sig = _signPayload(payload);
        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_ActiveLoanExists.selector);
        engine.openLoan(address(weth), 10e6, payload, sig);
    }

    // -------------------------------------------------------------------------
    // Withdraw blocked due to price drop
    // -------------------------------------------------------------------------

    function test_Withdraw_BlockedAfterPriceDrop() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);

        wethFeed.setPrice(0.5e8); // Price drops to $0.50

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_WithdrawWouldViolateLTV.selector);
        engine.withdrawCollateral(address(weth), 50e18);
    }

    // -------------------------------------------------------------------------
    // Decimals correctness (WBTC 8 decimals)
    // -------------------------------------------------------------------------

    function test_Decimals_WBTC_ConvertsCorrectly() public {
        vm.startPrank(borrower);
        creditRegistry.updateCreditProfile(_makePayload(850, 1), _signPayload(_makePayload(850, 1)));
        wbtc.approve(address(engine), 1e8);
        engine.depositCollateral(address(wbtc), 1e8);
        vm.stopPrank();

        uint256 maxBorrow = engine.getMaxBorrow(borrower, address(wbtc));
        assertEq(maxBorrow, 33_250e6); // 1 BTC @ 50k, 5% haircut, 70% LTV
    }

    // -------------------------------------------------------------------------
    // GetTerms, Interest accrual
    // -------------------------------------------------------------------------

    function test_GetTerms_ScoreBands() public {
        vm.startPrank(borrower);
        creditRegistry.updateCreditProfile(_makePayload(400, 10), _signPayload(_makePayload(400, 10)));
        vm.stopPrank();

        ILoanEngine.LoanTerms memory t400 = engine.getTerms(borrower);
        assertEq(t400.ltvBps, 6500);
        assertEq(t400.interestRateBps, 1000);

        vm.startPrank(borrower);
        creditRegistry.updateCreditProfile(_makePayload(700, 11), _signPayload(_makePayload(700, 11)));
        vm.stopPrank();

        ILoanEngine.LoanTerms memory t700 = engine.getTerms(borrower);
        assertEq(t700.ltvBps, 7500);
        assertEq(t700.interestRateBps, 700);

        vm.startPrank(borrower);
        creditRegistry.updateCreditProfile(_makePayload(900, 12), _signPayload(_makePayload(900, 12)));
        vm.stopPrank();

        ILoanEngine.LoanTerms memory t900 = engine.getTerms(borrower);
        assertEq(t900.ltvBps, 8500);
        assertEq(t900.interestRateBps, 500);
    }

    function test_AccruesInterestOverTime() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);
        vm.warp(block.timestamp + 30 days);

        ILoanEngine.LoanPosition memory pos = engine.getPosition(borrower);
        assertGt(pos.principalAmount, 50e6);
        assertApproxEqRel(pos.principalAmount, 50.288e6, 0.01e18);
    }

    function test_RepayAfterAccrual() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);
        vm.warp(block.timestamp + 30 days);

        uint256 debtBefore = engine.getPosition(borrower).principalAmount;
        vm.startPrank(borrower);
        usdc.approve(address(vault), 25e6);
        engine.repay(25e6);
        vm.stopPrank();

        assertEq(engine.getPosition(borrower).principalAmount, debtBefore - 25e6);
    }

    function test_WithdrawCollateralBlockedAfterAccrual() public {
        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);
        vm.warp(block.timestamp + 365 days);

        vm.prank(borrower);
        vm.expectRevert(LoanEngine.LoanEngine_WithdrawWouldViolateLTV.selector);
        engine.withdrawCollateral(address(weth), 50e18);
    }

    function test_TierIndexIndependent() public {
        vm.startPrank(borrower);
        weth.approve(address(engine), 200e18);
        engine.depositCollateral(address(weth), 200e18);
        vm.stopPrank();

        _depositAndOpenLoan(address(weth), 100e18, 750, 50e6);

        address borrowerB = makeAddr("borrowerB");
        weth.mint(borrowerB, 1000e18);
        vm.startPrank(borrowerB);
        weth.approve(address(engine), 100e18);
        engine.depositCollateral(address(weth), 100e18);
        IRiskOracle.RiskPayload memory p400 = IRiskOracle.RiskPayload({
            user: borrowerB,
            score: 400,
            riskTier: 2,
            timestamp: block.timestamp,
            nonce: 100
        });
        engine.openLoan(address(weth), 50e6, p400, _signPayload(p400));
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        assertGt(engine.getPosition(borrowerB).principalAmount, engine.getPosition(borrower).principalAmount);
    }

    function test_OpenLoan_FailsIfPayloadUserMismatch() public {
        vm.startPrank(borrower);
        weth.approve(address(engine), 100e18);
        engine.depositCollateral(address(weth), 100e18);
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
        engine.openLoan(address(weth), 75e6, payload, sig);
    }

    function test_OpenLoan_StalePrice_Reverts() public {
        vm.prank(owner);
        priceRouter.setStalePeriod(address(weth), 60);
        vm.warp(block.timestamp + 61);

        vm.startPrank(borrower);
        weth.approve(address(engine), 100e18);
        engine.depositCollateral(address(weth), 100e18);
        IRiskOracle.RiskPayload memory payload = _makePayload(750, 1);
        bytes memory sig = _signPayload(payload);
        vm.expectRevert(LoanEngine.LoanEngine_PriceStale.selector);
        engine.openLoan(address(weth), 75e6, payload, sig);
        vm.stopPrank();
    }
}
