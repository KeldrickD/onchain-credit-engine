// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AttestationRegistry} from "../../src/AttestationRegistry.sol";
import {RiskEngineV2} from "../../src/RiskEngineV2.sol";
import {MockLoanEngineForRisk} from "../mocks/MockLoanEngineForRisk.sol";

import {IAttestationRegistry} from "../../src/interfaces/IAttestationRegistry.sol";
import {IRiskEngineV2} from "../../src/interfaces/IRiskEngineV2.sol";

contract InvariantRiskDeterminism is Test {
    uint256 internal constant ISSUER_PK = 0xA11CE;

    address internal admin;
    address internal issuer;
    address internal walletSubject;
    bytes32 internal keyedSubject;

    AttestationRegistry internal attestationRegistry;
    MockLoanEngineForRisk internal mockLoan;
    RiskEngineV2 internal riskEngine;

    function setUp() external {
        admin = makeAddr("admin");
        issuer = vm.addr(ISSUER_PK);
        walletSubject = address(0xBEEF);
        keyedSubject = keccak256("DETERMINISM_SUBJECT");

        attestationRegistry = new AttestationRegistry(admin);
        mockLoan = new MockLoanEngineForRisk();
        riskEngine = new RiskEngineV2(address(attestationRegistry), address(mockLoan));

        vm.startPrank(admin);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuer);
        vm.stopPrank();

        _submitWalletAttestation("KYB_PASS", bytes32(0), keccak256("kyb"));
        _submitWalletAttestation("DSCR_BPS", bytes32(uint256(13_000)), keccak256("dscr"));
        _submitSubjectAttestation("DSCR_BPS", bytes32(uint256(13_000)), keccak256("subject_dscr"));
        _submitSubjectAttestation("SPONSOR_TRACK", bytes32(0), keccak256("subject_sponsor"));
    }

    function test_EvaluateWallet_IsDeterministicWithinBlock() external view {
        IRiskEngineV2.RiskOutput memory a = riskEngine.evaluate(walletSubject);
        IRiskEngineV2.RiskOutput memory b = riskEngine.evaluate(walletSubject);

        assertEq(keccak256(abi.encode(a.reasonCodes)), keccak256(abi.encode(b.reasonCodes)));
        assertEq(keccak256(abi.encode(a.evidence)), keccak256(abi.encode(b.evidence)));
        assertEq(a.score, b.score);
        assertEq(a.confidenceBps, b.confidenceBps);
        assertEq(a.tier, b.tier);
    }

    function test_EvaluateSubject_IsDeterministicWithinBlock() external view {
        IRiskEngineV2.RiskOutput memory a = riskEngine.evaluateSubject(keyedSubject);
        IRiskEngineV2.RiskOutput memory b = riskEngine.evaluateSubject(keyedSubject);

        assertEq(keccak256(abi.encode(a.reasonCodes)), keccak256(abi.encode(b.reasonCodes)));
        assertEq(keccak256(abi.encode(a.evidence)), keccak256(abi.encode(b.evidence)));
        assertEq(a.score, b.score);
        assertEq(a.confidenceBps, b.confidenceBps);
        assertEq(a.tier, b.tier);
    }

    function _submitWalletAttestation(string memory typeStr, bytes32 data, bytes32 dataHash) internal {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: walletSubject,
            attestationType: keccak256(bytes(typeStr)),
            dataHash: dataHash,
            data: data,
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextNonce(walletSubject)
        });
        bytes32 digest = attestationRegistry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, digest);
        attestationRegistry.submitAttestation(a, abi.encodePacked(r, s, v));
    }

    function _submitSubjectAttestation(string memory typeStr, bytes32 data, bytes32 dataHash) internal {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: keyedSubject,
            attestationType: keccak256(bytes(typeStr)),
            dataHash: dataHash,
            data: data,
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextSubjectNonce(keyedSubject)
        });
        bytes32 digest = attestationRegistry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, digest);
        attestationRegistry.submitSubjectAttestation(a, abi.encodePacked(r, s, v));
    }
}
