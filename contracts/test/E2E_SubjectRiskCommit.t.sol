// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RiskOracle} from "../src/RiskOracle.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {RiskEngineV2} from "../src/RiskEngineV2.sol";
import {SubjectRegistry} from "../src/SubjectRegistry.sol";
import {MockLoanEngineForRisk} from "./mocks/MockLoanEngineForRisk.sol";

import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {IRiskEngineV2} from "../src/interfaces/IRiskEngineV2.sol";
import {ICreditRegistry} from "../src/interfaces/ICreditRegistry.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";
import {ISubjectRegistry} from "../src/interfaces/ISubjectRegistry.sol";

/// @title E2E Subject (Deal) Risk Commit
/// @notice Proves CapitalMethod path: deal subject -> attestations -> evaluateSubject -> signed commit by key
contract E2ESubjectRiskCommitTest is Test {
    uint256 internal constant ORACLE_PK = 0xA11CE;
    address internal oracleSigner;
    address internal admin;
    address internal sponsor;

    RiskOracle internal riskOracle;
    CreditRegistry internal creditRegistry;
    AttestationRegistry internal attestationRegistry;
    RiskEngineV2 internal riskEngine;
    SubjectRegistry internal subjectRegistry;
    MockLoanEngineForRisk internal mockLoan;

    bytes32 internal dealSubjectId;
    bytes32 internal constant DEAL = keccak256("DEAL");

    function setUp() public {
        vm.warp(1_000);

        oracleSigner = vm.addr(ORACLE_PK);
        admin = makeAddr("admin");
        sponsor = makeAddr("sponsor");

        riskOracle = new RiskOracle(oracleSigner);
        creditRegistry = new CreditRegistry(address(riskOracle));
        attestationRegistry = new AttestationRegistry(admin);
        mockLoan = new MockLoanEngineForRisk();
        riskEngine = new RiskEngineV2(address(attestationRegistry), address(mockLoan));
        subjectRegistry = new SubjectRegistry();

        vm.prank(admin);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), oracleSigner);

        vm.prank(sponsor);
        dealSubjectId = subjectRegistry.createSubjectWithNonce(DEAL);
    }

    function test_E2E_DealSubject_Attestations_EvaluateSubject_CommitByKey_WalletUnaffected() public {
        _submitSubjectAttestation(dealSubjectId, "DSCR_BPS", bytes32(uint256(13_000)), keccak256("dscr"), "");
        _submitSubjectAttestation(dealSubjectId, "NOI_USD6", bytes32(uint256(120_000_000)), keccak256("noi"), "");
        _submitSubjectAttestation(dealSubjectId, "SPONSOR_TRACK", bytes32(0), keccak256("sp"), "");

        IRiskEngineV2.RiskOutput memory out = riskEngine.evaluateSubject(dealSubjectId);
        assertGt(out.score, 480, "score should improve with attestations");
        assertGt(out.confidenceBps, 1500, "confidence should improve");

        bytes32 reasonsHash = keccak256(abi.encode(out.reasonCodes));
        bytes32 evidenceHash = keccak256(abi.encode(out.evidence));

        IRiskOracle.RiskPayloadV2ByKey memory p = IRiskOracle.RiskPayloadV2ByKey({
            subjectKey: dealSubjectId,
            score: out.score,
            riskTier: out.tier,
            confidenceBps: out.confidenceBps,
            modelId: out.modelId,
            reasonsHash: reasonsHash,
            evidenceHash: evidenceHash,
            timestamp: uint64(block.timestamp),
            nonce: riskOracle.nextNonceKey(dealSubjectId)
        });
        bytes memory sig = _signPayloadV2ByKey(p);

        creditRegistry.updateCreditProfileV2ByKey(p, sig);

        ICreditRegistry.CreditProfile memory profile = creditRegistry.getProfile(dealSubjectId);
        assertEq(profile.score, out.score);
        assertEq(profile.riskTier, out.tier);
        assertEq(profile.confidenceBps, out.confidenceBps);
        assertEq(profile.modelId, out.modelId);
        assertEq(profile.reasonsHash, reasonsHash);
        assertEq(profile.evidenceHash, evidenceHash);

        address wallet = makeAddr("wallet");
        ICreditRegistry.CreditProfile memory walletProfile = creditRegistry.getCreditProfile(wallet);
        assertEq(walletProfile.score, 0, "wallet profile must be unaffected");
        assertEq(walletProfile.riskTier, 0);
    }

    function _submitSubjectAttestation(
        bytes32 subjectId,
        string memory typeStr,
        bytes32 data,
        bytes32 dataHash,
        string memory uri
    ) internal {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: subjectId,
            attestationType: keccak256(bytes(typeStr)),
            dataHash: dataHash,
            data: data,
            uri: uri,
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextSubjectNonce(subjectId)
        });

        bytes32 digest = attestationRegistry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        attestationRegistry.submitSubjectAttestation(a, sig);
    }

    function _signPayloadV2ByKey(IRiskOracle.RiskPayloadV2ByKey memory payload)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = riskOracle.getPayloadDigestV2ByKey(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}
