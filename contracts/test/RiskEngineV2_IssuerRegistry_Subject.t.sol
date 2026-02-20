// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskEngineV2} from "../src/RiskEngineV2.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {MockLoanEngineForRisk} from "./mocks/MockLoanEngineForRisk.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";
import {IRiskEngineV2} from "../src/interfaces/IRiskEngineV2.sol";

contract RiskEngineV2IssuerRegistrySubjectTest is Test {
    RiskEngineV2 internal engine;
    AttestationRegistry internal attestationRegistry;
    IssuerRegistry internal issuerRegistry;
    MockLoanEngineForRisk internal mockLoan;

    uint256 internal constant ISSUER_LOW_PK = 0x2001;
    uint256 internal constant ISSUER_MID_PK = 0x2002;
    uint256 internal constant ISSUER_HIGH_PK = 0x2003;
    address internal issuerLow;
    address internal issuerMid;
    address internal issuerHigh;
    address internal admin;
    bytes32 internal subjectId;

    bytes32 internal constant DSCR_BPS = keccak256("DSCR_BPS");

    function setUp() public {
        vm.warp(1000);
        admin = makeAddr("admin");
        subjectId = keccak256("subject:weighted");
        issuerLow = vm.addr(ISSUER_LOW_PK);
        issuerMid = vm.addr(ISSUER_MID_PK);
        issuerHigh = vm.addr(ISSUER_HIGH_PK);

        attestationRegistry = new AttestationRegistry(admin);
        issuerRegistry = new IssuerRegistry(admin);
        mockLoan = new MockLoanEngineForRisk();
        engine = new RiskEngineV2(address(attestationRegistry), address(mockLoan));

        vm.startPrank(admin);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuerLow);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuerMid);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuerHigh);

        issuerRegistry.setIssuer(issuerLow, true, 3000, bytes32(0), "ipfs://low");
        issuerRegistry.setIssuer(issuerMid, true, 5000, bytes32(0), "ipfs://mid");
        issuerRegistry.setIssuer(issuerHigh, true, 10000, bytes32(0), "ipfs://high");
        issuerRegistry.setIssuerTypePermission(issuerLow, DSCR_BPS, true);
        issuerRegistry.setIssuerTypePermission(issuerMid, DSCR_BPS, true);
        issuerRegistry.setIssuerTypePermission(issuerHigh, DSCR_BPS, true);
        issuerRegistry.setMinTrustScoreBpsForType(DSCR_BPS, 7000);
        vm.stopPrank();
    }

    function _submitSubjectDscr(bytes32 subj, uint256 issuerPk, bytes32 dataHash) internal returns (bytes32 id) {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: subj,
            attestationType: DSCR_BPS,
            dataHash: dataHash,
            data: bytes32(uint256(13_000)),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextSubjectNonce(subj)
        });
        bytes32 digest = attestationRegistry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        return attestationRegistry.submitSubjectAttestation(a, abi.encodePacked(r, s, v));
    }

    function test_LegacyModeSubjectUnchanged() public {
        bytes32 id = _submitSubjectDscr(subjectId, ISSUER_LOW_PK, keccak256("legacy-subject"));
        assertEq(engine.issuerRegistry(), address(0));

        IRiskEngineV2.RiskOutput memory out = engine.evaluateSubject(subjectId);
        assertEq(out.score, 640); // 480 + 160
        assertEq(out.confidenceBps, 4000); // 1500 + 2500
        assertEq(out.reasonCodes.length, 2); // SUBJECT_MODE + DSCR_STRONG
        assertEq(out.reasonCodes[0], engine.REASON_SUBJECT_MODE());
        assertEq(out.reasonCodes[1], engine.REASON_DSCR_STRONG());
        assertEq(out.evidence.length, 1);
        assertEq(out.evidence[0], id);
    }

    function test_WeightedModeSubjectTrustedMatchesLegacyWith10000Trust() public {
        _submitSubjectDscr(subjectId, ISSUER_HIGH_PK, keccak256("trusted-subject"));
        engine.setIssuerRegistry(address(issuerRegistry));

        IRiskEngineV2.RiskOutput memory out = engine.evaluateSubject(subjectId);
        assertEq(out.score, 640);
        assertEq(out.confidenceBps, 4000);
        assertEq(out.reasonCodes[1], engine.REASON_DSCR_STRONG());
    }

    function test_WeightedModeSubjectMidTrustHalfScoreDelta() public {
        bytes32 id = _submitSubjectDscr(subjectId, ISSUER_MID_PK, keccak256("mid-subject"));
        engine.setIssuerRegistry(address(issuerRegistry));

        IRiskEngineV2.RiskOutput memory out = engine.evaluateSubject(subjectId);
        assertEq(out.score, 560); // 480 + (160/2)
        assertEq(out.confidenceBps, 2750); // 1500 + (2500 * 0.5)
        assertEq(out.reasonCodes[1], engine.REASON_UNTRUSTED_DSCR());
        assertEq(out.evidence[0], id);
    }

    function test_WeightedModeSubjectLowTrustZeroScoreDelta() public {
        bytes32 id = _submitSubjectDscr(subjectId, ISSUER_LOW_PK, keccak256("low-subject"));
        engine.setIssuerRegistry(address(issuerRegistry));

        IRiskEngineV2.RiskOutput memory out = engine.evaluateSubject(subjectId);
        assertEq(out.score, 480); // no DSCR score delta
        assertEq(out.confidenceBps, 2250); // 1500 + (2500 * 0.3)
        assertEq(out.reasonCodes[1], engine.REASON_UNTRUSTED_DSCR());
        assertEq(out.evidence[0], id);
    }
}
