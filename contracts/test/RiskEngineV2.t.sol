// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskEngineV2} from "../src/RiskEngineV2.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {MockLoanEngineForRisk} from "./mocks/MockLoanEngineForRisk.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";
import {IRiskEngineV2} from "../src/interfaces/IRiskEngineV2.sol";

contract RiskEngineV2Test is Test {
    RiskEngineV2 public engine;
    AttestationRegistry public registry;
    MockLoanEngineForRisk public mockLoan;
    address public admin;
    address public issuer;
    address public subject;
    address public collateralAsset;

    uint256 constant ISSUER_KEY = 0xA11CE;

    bytes32 constant KYB_PASS = keccak256("KYB_PASS");
    bytes32 constant DSCR_BPS = keccak256("DSCR_BPS");
    bytes32 constant NOI_USD6 = keccak256("NOI_USD6");
    bytes32 constant SPONSOR_TRACK = keccak256("SPONSOR_TRACK");

    function setUp() public {
        vm.warp(1000);
        admin = makeAddr("admin");
        issuer = vm.addr(ISSUER_KEY);
        subject = makeAddr("subject");
        collateralAsset = makeAddr("collateral");

        registry = new AttestationRegistry(admin);
        bytes32 issuerRole = registry.ISSUER_ROLE();
        vm.prank(admin);
        registry.grantRole(issuerRole, issuer);

        mockLoan = new MockLoanEngineForRisk();
        engine = new RiskEngineV2(address(registry), address(mockLoan));
    }

    function _submitAttestation(
        address subj,
        bytes32 aType,
        bytes32 dataHash,
        bytes32 data,
        string memory uri,
        uint64 expiresAt
    ) internal returns (bytes32) {
        uint64 nonce = registry.nextNonce(subj);
        uint64 issuedAt = uint64(block.timestamp);
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: subj,
            attestationType: aType,
            dataHash: dataHash,
            data: data,
            uri: uri,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            nonce: nonce
        });
        bytes32 digest = registry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_KEY, digest);
        return registry.submitAttestation(a, abi.encodePacked(r, s, v));
    }

    function test_NoAttestations_NoDebt_BaseScoreLowConfidence() public {
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 520, "base score");
        assertEq(out.tier, 1, "400-699 tier");
        assertEq(out.confidenceBps, 1500, "base confidence");
        assertEq(out.reasonCodes.length, 0);
        assertEq(out.evidence.length, 0);
    }

    function test_KYBDSCRSponsor_ScoreIncreases_EvidenceIncluded() public {
        _submitAttestation(subject, KYB_PASS, keccak256("kyb"), bytes32(0), "", 0);
        _submitAttestation(subject, DSCR_BPS, keccak256("dscr"), bytes32(uint256(13000)), "", 0);
        _submitAttestation(subject, SPONSOR_TRACK, keccak256("sp"), bytes32(0), "", 0);

        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        // 520 + 120 + 160 + 80 = 880
        assertEq(out.score, 880);
        assertEq(out.tier, 3, ">850");
        assertTrue(out.confidenceBps > 1500, "confidence increased");
        assertEq(out.reasonCodes.length, 3);
        assertEq(out.evidence.length, 3);
    }

    function test_UtilizationHigh_ScorePenalty() public {
        mockLoan.setPosition(subject, collateralAsset, 100e18, 85e6, 8500, 700);
        mockLoan.setMaxBorrow(subject, collateralAsset, 100e6);
        mockLoan.setLastRepayAt(subject, uint64(block.timestamp));
        // util = 85/100 = 85% -> UTIL_HIGH
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 400, "520 - 120");
        assertEq(out.reasonCodes.length, 1);
        assertEq(out.reasonCodes[0], engine.REASON_UTIL_HIGH());
    }

    function test_LiquidationCount_PenaltyAndReason() public {
        mockLoan.setLiquidationCount(subject, 1);
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 270, "520 - 250");
        assertEq(out.reasonCodes.length, 1);
        assertEq(out.reasonCodes[0], engine.REASON_HAS_LIQUIDATIONS());
    }

    function test_ExpiredAttestation_Ignored() public {
        _submitAttestation(subject, KYB_PASS, keccak256("x"), bytes32(0), "", uint64(block.timestamp + 3600));
        vm.warp(block.timestamp + 3601);

        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 520, "expired KYB not counted");
        assertEq(out.reasonCodes.length, 0);
    }

    function test_DscrWeak_Penalty() public {
        _submitAttestation(subject, DSCR_BPS, keccak256("d"), bytes32(uint256(10000)), "", 0);
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 400, "520 - 120");
        assertEq(out.reasonCodes[0], engine.REASON_DSCR_WEAK());
    }

    function test_RepayStale_Penalty() public {
        vm.warp(31 days + 1000);
        mockLoan.setPosition(subject, collateralAsset, 100e18, 50e6, 5000, 700);
        mockLoan.setMaxBorrow(subject, collateralAsset, 100e6);
        mockLoan.setLastRepayAt(subject, uint64(block.timestamp - 31 days - 1));
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 440, "520 - 80");
        assertEq(out.reasonCodes[0], engine.REASON_REPAY_STALE());
    }

    function test_UtilLow_Bonus() public {
        mockLoan.setPosition(subject, collateralAsset, 100e18, 30e6, 3000, 700);
        mockLoan.setMaxBorrow(subject, collateralAsset, 100e6);
        mockLoan.setLastRepayAt(subject, uint64(block.timestamp));
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 560, "520 + 40");
        assertEq(out.reasonCodes[0], engine.REASON_UTIL_LOW());
    }
}
