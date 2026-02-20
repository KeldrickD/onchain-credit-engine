// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskEngineV2} from "../src/RiskEngineV2.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {MockLoanEngineForRisk} from "./mocks/MockLoanEngineForRisk.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";
import {IRiskEngineV2} from "../src/interfaces/IRiskEngineV2.sol";

/// @notice Golden vectors for trust-weighted policy:
/// legacy (unset issuerRegistry) vs weighted (full/half/zero score + confidence scaling).
contract RiskEngineV2GoldenVectorsTest is Test {
    struct Vec {
        bool legacy;
        uint16 trustBps;
        bool active;
        bool allowed;
        uint16 minTrustBps;
    }

    uint256 internal constant ISSUER_PK = 0xA11CE;
    bytes32 internal constant KYB_PASS = keccak256("KYB_PASS");
    bytes32 internal constant DSCR_BPS = keccak256("DSCR_BPS");
    bytes32 internal constant SPONSOR_TRACK = keccak256("SPONSOR_TRACK");

    uint16 internal constant TRUST_HALF_THRESHOLD = 4_000;
    uint256 internal constant CONF_BASE = 1500;
    uint256 internal constant CONF_FACTORS = 2000 + 2500 + 1000; // KYB + DSCR + SPONSOR
    int256 internal constant FULL_DELTA_WALLET = 120 + 160 + 80; // KYB + DSCR_STRONG + SPONSOR
    int256 internal constant FULL_DELTA_SUBJECT = 150 + 160 + 100; // subject KYB + DSCR_STRONG + SPONSOR

    function test_GoldenVectors_Wallet() public {
        Vec[7] memory vecs = _vectors();
        for (uint256 i = 0; i < vecs.length; i++) {
            _runWalletVector(vecs[i]);
        }
    }

    function test_GoldenVectors_Subject() public {
        Vec[7] memory vecs = _vectors();
        for (uint256 i = 0; i < vecs.length; i++) {
            _runSubjectVector(vecs[i]);
        }
    }

    function _runWalletVector(Vec memory v) internal {
        (RiskEngineV2 engine, AttestationRegistry att, IssuerRegistry issuers, address subject, address issuer) = _deployStack();
        _configureIssuer(att, issuers, issuer, v.trustBps, v.active, v.allowed, v.minTrustBps);
        _submitWalletBaseline(att, subject);

        IRiskEngineV2.RiskOutput memory baseline = engine.evaluate(subject);
        if (!v.legacy) {
            engine.setIssuerRegistry(address(issuers));
        }
        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);

        (uint16 expectedScore, uint16 expectedConf, bool expectUntrusted) =
            _expectedTuple(v, baseline.score, baseline.confidenceBps, FULL_DELTA_WALLET);

        assertEq(out.score, expectedScore);
        assertEq(out.tier, uint8(_scoreToTier(expectedScore)));
        assertEq(out.confidenceBps, expectedConf);
        assertEq(out.evidence.length, 3); // evidence always included for valid attestations

        bool hasUntrustedDscr = _contains(out.reasonCodes, engine.REASON_UNTRUSTED_DSCR());
        assertEq(hasUntrustedDscr, expectUntrusted);
    }

    function _runSubjectVector(Vec memory v) internal {
        (RiskEngineV2 engine, AttestationRegistry att, IssuerRegistry issuers,, address issuer) = _deployStack();
        _configureIssuer(att, issuers, issuer, v.trustBps, v.active, v.allowed, v.minTrustBps);
        bytes32 subjectId = keccak256("golden-subject");
        _submitSubjectBaseline(att, subjectId);

        IRiskEngineV2.RiskOutput memory baseline = engine.evaluateSubject(subjectId);
        if (!v.legacy) {
            engine.setIssuerRegistry(address(issuers));
        }
        IRiskEngineV2.RiskOutput memory out = engine.evaluateSubject(subjectId);

        (uint16 expectedScore, uint16 expectedConf, bool expectUntrusted) =
            _expectedTuple(v, baseline.score, baseline.confidenceBps, FULL_DELTA_SUBJECT);

        assertEq(out.score, expectedScore);
        assertEq(out.tier, uint8(_scoreToTier(expectedScore)));
        assertEq(out.confidenceBps, expectedConf);
        assertEq(out.evidence.length, 3); // evidence always included for valid attestations
        assertEq(out.reasonCodes[0], engine.REASON_SUBJECT_MODE());

        bool hasUntrustedDscr = _contains(out.reasonCodes, engine.REASON_UNTRUSTED_DSCR());
        assertEq(hasUntrustedDscr, expectUntrusted);
    }

    function _expectedTuple(Vec memory v, uint16 baselineScore, uint16 baselineConf, int256 fullDelta)
        internal
        pure
        returns (uint16 expectedScore, uint16 expectedConf, bool expectUntrusted)
    {
        if (v.legacy) {
            return (baselineScore, baselineConf, false);
        }

        bool trusted = v.active && v.allowed && v.trustBps >= v.minTrustBps;
        expectUntrusted = !trusted;

        int256 score = int256(uint256(baselineScore));
        if (trusted) {
            // trusted => same score as legacy baseline
        } else if (v.trustBps >= TRUST_HALF_THRESHOLD) {
            score -= fullDelta / 2;
        } else {
            score -= fullDelta;
        }
        expectedScore = uint16(uint256(score));

        // weighted mode: confidence always scales by trust bps for attestation-driven factors.
        expectedConf = uint16(CONF_BASE + ((CONF_FACTORS * v.trustBps) / 10_000));
    }

    function _configureIssuer(
        AttestationRegistry att,
        IssuerRegistry issuers,
        address issuer,
        uint16 trustBps,
        bool active,
        bool allowed,
        uint16 minTrustBps
    ) internal {
        address admin = makeAddr("admin");
        vm.startPrank(admin);
        att.grantRole(att.ISSUER_ROLE(), issuer);

        issuers.setIssuer(issuer, active, trustBps, bytes32(0), "ipfs://issuer");
        issuers.setIssuerTypePermission(issuer, DSCR_BPS, allowed);
        issuers.setIssuerTypePermission(issuer, KYB_PASS, allowed);
        issuers.setIssuerTypePermission(issuer, SPONSOR_TRACK, allowed);
        issuers.setMinTrustScoreBpsForType(DSCR_BPS, minTrustBps);
        issuers.setMinTrustScoreBpsForType(KYB_PASS, minTrustBps);
        issuers.setMinTrustScoreBpsForType(SPONSOR_TRACK, minTrustBps);
        vm.stopPrank();
    }

    function _submitWalletBaseline(AttestationRegistry att, address subject) internal {
        _submitWallet(att, subject, KYB_PASS, bytes32(0), keccak256("kyb"));
        _submitWallet(att, subject, DSCR_BPS, bytes32(uint256(13_000)), keccak256("dscr"));
        _submitWallet(att, subject, SPONSOR_TRACK, bytes32(0), keccak256("sp"));
    }

    function _submitSubjectBaseline(AttestationRegistry att, bytes32 subjectId) internal {
        _submitSubject(att, subjectId, KYB_PASS, bytes32(0), keccak256("kyb"));
        _submitSubject(att, subjectId, DSCR_BPS, bytes32(uint256(13_000)), keccak256("dscr"));
        _submitSubject(att, subjectId, SPONSOR_TRACK, bytes32(0), keccak256("sp"));
    }

    function _submitWallet(AttestationRegistry att, address subject, bytes32 aType, bytes32 data, bytes32 dataHash)
        internal
    {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: subject,
            attestationType: aType,
            dataHash: dataHash,
            data: data,
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: att.nextNonce(subject)
        });
        bytes32 digest = att.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, digest);
        att.submitAttestation(a, abi.encodePacked(r, s, v));
    }

    function _submitSubject(AttestationRegistry att, bytes32 subjectId, bytes32 aType, bytes32 data, bytes32 dataHash)
        internal
    {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: subjectId,
            attestationType: aType,
            dataHash: dataHash,
            data: data,
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: att.nextSubjectNonce(subjectId)
        });
        bytes32 digest = att.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, digest);
        att.submitSubjectAttestation(a, abi.encodePacked(r, s, v));
    }

    function _deployStack()
        internal
        returns (RiskEngineV2 engine, AttestationRegistry att, IssuerRegistry issuers, address subject, address issuer)
    {
        address admin = makeAddr("admin");
        issuer = vm.addr(ISSUER_PK);
        subject = makeAddr("subject");

        att = new AttestationRegistry(admin);
        issuers = new IssuerRegistry(admin);
        MockLoanEngineForRisk mockLoan = new MockLoanEngineForRisk();
        engine = new RiskEngineV2(address(att), address(mockLoan));
    }

    function _contains(bytes32[] memory arr, bytes32 x) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == x) return true;
        }
        return false;
    }

    function _scoreToTier(uint256 score) internal pure returns (uint256) {
        if (score < 400) return 0;
        if (score < 700) return 1;
        if (score <= 850) return 2;
        return 3;
    }

    function _vectors() internal pure returns (Vec[7] memory vecs) {
        // 1) legacy mode
        vecs[0] = Vec({legacy: true, trustBps: 3000, active: true, allowed: true, minTrustBps: 7000});
        // 2) weighted trusted
        vecs[1] = Vec({legacy: false, trustBps: 10000, active: true, allowed: true, minTrustBps: 7000});
        // 3) weighted mid trust (untrusted by minTrust, half score)
        vecs[2] = Vec({legacy: false, trustBps: 5000, active: true, allowed: true, minTrustBps: 7000});
        // 4) weighted low trust (untrusted, zero score)
        vecs[3] = Vec({legacy: false, trustBps: 3000, active: true, allowed: true, minTrustBps: 7000});
        // 5) inactive (untrusted, trust>=4000 => half score)
        vecs[4] = Vec({legacy: false, trustBps: 9000, active: false, allowed: true, minTrustBps: 7000});
        // 6) disallowed type (untrusted, trust>=4000 => half score)
        vecs[5] = Vec({legacy: false, trustBps: 9000, active: true, allowed: false, minTrustBps: 7000});
        // 7) minTrust raised over trust (untrusted, trust>=4000 => half score)
        vecs[6] = Vec({legacy: false, trustBps: 9000, active: true, allowed: true, minTrustBps: 9500});
    }
}
