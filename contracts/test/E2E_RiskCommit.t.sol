// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RiskOracle} from "../src/RiskOracle.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {LoanEngine} from "../src/LoanEngine.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {PriceRouter} from "../src/PriceRouter.sol";
import {SignedPriceOracle} from "../src/SignedPriceOracle.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {RiskEngineV2} from "../src/RiskEngineV2.sol";

import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockCollateral} from "./mocks/MockCollateral.sol";

import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {IRiskEngineV2} from "../src/interfaces/IRiskEngineV2.sol";
import {ICreditRegistry} from "../src/interfaces/ICreditRegistry.sol";
import {IPriceRouter} from "../src/interfaces/IPriceRouter.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {ICollateralManager} from "../src/interfaces/ICollateralManager.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";
import {ILoanEngine} from "../src/interfaces/ILoanEngine.sol";

contract E2ERiskCommitTest is Test {
    uint256 internal constant ORACLE_PK = 0xA11CE;
    address internal oracleSigner;
    address internal admin;
    address internal borrower;

    MockUSDC internal usdc;
    MockCollateral internal weth;

    RiskOracle internal riskOracle;
    CreditRegistry internal creditRegistry;
    LoanEngine internal loanEngine;
    SignedPriceOracle internal signedPriceOracle;
    PriceRouter internal priceRouter;
    CollateralManager internal collateralManager;
    TreasuryVault internal vault;
    LiquidationManager internal liquidationManager;
    AttestationRegistry internal attestationRegistry;
    RiskEngineV2 internal riskEngine;

    function setUp() public {
        vm.warp(1_000);

        oracleSigner = vm.addr(ORACLE_PK);
        admin = makeAddr("admin");
        borrower = makeAddr("borrower");

        usdc = new MockUSDC();
        weth = new MockCollateral();

        signedPriceOracle = new SignedPriceOracle(oracleSigner);
        priceRouter = new PriceRouter();
        collateralManager = new CollateralManager();
        riskOracle = new RiskOracle(oracleSigner);
        creditRegistry = new CreditRegistry(address(riskOracle));
        vault = new TreasuryVault(address(usdc), admin);

        loanEngine = new LoanEngine(
            address(creditRegistry), address(vault), address(usdc), address(priceRouter), address(collateralManager)
        );

        liquidationManager = new LiquidationManager(
            address(loanEngine), address(collateralManager), address(usdc), address(vault), address(priceRouter)
        );

        attestationRegistry = new AttestationRegistry(admin);
        riskEngine = new RiskEngineV2(address(attestationRegistry), address(loanEngine));

        priceRouter.transferOwnership(admin);
        collateralManager.transferOwnership(admin);

        vm.startPrank(admin);
        collateralManager.setLoanEngine(address(loanEngine));
        vault.setLoanEngine(address(loanEngine));
        loanEngine.setLiquidationManager(address(liquidationManager));
        vault.setLiquidationManager(address(liquidationManager));

        priceRouter.setSignedOracle(address(weth), address(signedPriceOracle));
        priceRouter.setSource(address(weth), IPriceRouter.Source.SIGNED);
        priceRouter.setStalePeriod(address(weth), 3600);

        collateralManager.setConfig(
            address(weth),
            ICollateralManager.CollateralConfig({
                enabled: true,
                ltvBpsCap: 9000,
                liquidationThresholdBpsCap: 9500,
                haircutBps: 9500,
                debtCeilingUSDC6: 0
            })
        );

        usdc.mint(admin, 1_000_000e6);
        usdc.transfer(address(vault), 500_000e6);

        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), oracleSigner);
        vm.stopPrank();

        weth.mint(borrower, 10e18);
        _pushSignedPriceUSD8(address(weth), 2500e8);

        vm.startPrank(borrower);
        weth.approve(address(loanEngine), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_E2E_AttestationsEvaluateSignV2CommitThenOpenLoan_PositionTermsFreeze() public {
        _submitAttestationAsIssuer(borrower, "KYB_PASS", bytes32(0), keccak256("kyb"), "");
        _submitAttestationAsIssuer(
            borrower, "DSCR_BPS", bytes32(uint256(13_000)), keccak256(abi.encode(uint256(13_000))), ""
        );
        _submitAttestationAsIssuer(borrower, "SPONSOR_TRACK", bytes32(0), keccak256("sponsor_track"), "");

        IRiskEngineV2.RiskOutput memory out = riskEngine.evaluate(borrower);
        assertGt(out.score, 520, "score should improve with attestations");
        assertGt(out.confidenceBps, 1500, "confidence should improve");
        assertGt(out.reasonCodes.length, 0, "reasons expected");

        bytes32 reasonsHash = keccak256(abi.encode(out.reasonCodes));
        bytes32 evidenceHash = keccak256(abi.encode(out.evidence));

        IRiskOracle.RiskPayloadV2 memory payloadV2 = IRiskOracle.RiskPayloadV2({
            user: borrower,
            score: out.score,
            riskTier: out.tier,
            confidenceBps: out.confidenceBps,
            modelId: out.modelId,
            reasonsHash: reasonsHash,
            evidenceHash: evidenceHash,
            timestamp: uint64(block.timestamp),
            nonce: uint64(riskOracle.nextNonce(borrower))
        });
        bytes memory sigV2 = _signRiskPayloadV2(payloadV2);

        creditRegistry.updateCreditProfileV2(payloadV2, sigV2);

        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(borrower);
        assertEq(profile.score, out.score);
        assertEq(profile.riskTier, out.tier);
        assertEq(profile.confidenceBps, out.confidenceBps);
        assertEq(profile.modelId, out.modelId);
        assertEq(profile.reasonsHash, reasonsHash);
        assertEq(profile.evidenceHash, evidenceHash);

        vm.startPrank(borrower);
        loanEngine.depositCollateral(address(weth), 2e18);
        uint256 maxBorrowBefore = loanEngine.getMaxBorrow(borrower, address(weth));
        assertGt(maxBorrowBefore, 0, "maxBorrow should be positive");

        uint256 expectedFrozenRate = _expectedRateForScore(out.score);
        IRiskOracle.RiskPayload memory openPayload = IRiskOracle.RiskPayload({
            user: borrower,
            score: out.score,
            riskTier: out.tier,
            timestamp: block.timestamp,
            nonce: riskOracle.nextNonce(borrower)
        });
        loanEngine.openLoan(address(weth), maxBorrowBefore / 4, openPayload, _signRiskPayload(openPayload));

        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(borrower);
        assertEq(pos.collateralAsset, address(weth));
        assertEq(pos.interestRateBps, expectedFrozenRate, "position rate should freeze at open");
        vm.stopPrank();

        IRiskOracle.RiskPayloadV2 memory downgraded = IRiskOracle.RiskPayloadV2({
            user: borrower,
            score: 350,
            riskTier: 0,
            confidenceBps: 1000,
            modelId: out.modelId,
            reasonsHash: keccak256(abi.encode(new bytes32[](0))),
            evidenceHash: keccak256(abi.encode(new bytes32[](0))),
            timestamp: uint64(block.timestamp),
            nonce: uint64(riskOracle.nextNonce(borrower))
        });
        creditRegistry.updateCreditProfileV2(downgraded, _signRiskPayloadV2(downgraded));

        ILoanEngine.LoanPosition memory posAfterDowngrade = loanEngine.getPosition(borrower);
        assertEq(
            posAfterDowngrade.interestRateBps, expectedFrozenRate, "position rate must remain frozen after downgrade"
        );

        ILoanEngine.LoanTerms memory liveTermsAfter = loanEngine.getTerms(borrower);
        assertEq(liveTermsAfter.interestRateBps, _expectedRateForScore(350), "live terms should reflect downgrade");

        uint256 maxBorrowAfter = loanEngine.getMaxBorrow(borrower, address(weth));
        assertLt(maxBorrowAfter, maxBorrowBefore, "live maxBorrow should drop after downgrade");
    }

    function _pushSignedPriceUSD8(address asset, uint256 priceUSD8) internal {
        IPriceOracle.PricePayload memory pp = IPriceOracle.PricePayload({
            asset: asset,
            price: priceUSD8,
            timestamp: block.timestamp,
            nonce: signedPriceOracle.nextNonce(asset)
        });

        bytes32 digest = signedPriceOracle.getPricePayloadDigest(pp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(admin);
        priceRouter.updateSignedPriceAndGet(asset, pp, sig);
    }

    function _submitAttestationAsIssuer(
        address subject,
        string memory typeStr,
        bytes32 data,
        bytes32 dataHash,
        string memory uri
    ) internal {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: subject,
            attestationType: keccak256(bytes(typeStr)),
            dataHash: dataHash,
            data: data,
            uri: uri,
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextNonce(subject)
        });

        bytes32 digest = attestationRegistry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        attestationRegistry.submitAttestation(a, sig);
    }

    function _signRiskPayload(IRiskOracle.RiskPayload memory payload) internal view returns (bytes memory) {
        bytes32 digest = riskOracle.getPayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signRiskPayloadV2(IRiskOracle.RiskPayloadV2 memory payload) internal view returns (bytes memory) {
        bytes32 digest = riskOracle.getPayloadDigestV2(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    function _expectedRateForScore(uint256 score) internal pure returns (uint256) {
        if (score >= 851) return 500;
        if (score >= 700) return 700;
        if (score >= 400) return 1000;
        return 1500;
    }
}
