// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";

contract RiskOracleTest is Test {
    RiskOracle public oracle;

    uint256 public constant ORACLE_PRIVATE_KEY = 0xA11CE;
    uint256 public constant WRONG_PRIVATE_KEY = 0xB0B;
    address public oracleSigner;
    address public wrongSigner;
    address public user;

    function setUp() public {
        oracleSigner = vm.addr(ORACLE_PRIVATE_KEY);
        wrongSigner = vm.addr(WRONG_PRIVATE_KEY);
        user = makeAddr("user");

        // Warp time so timestamp arithmetic (block.timestamp - 400, etc.) doesn't underflow
        vm.warp(1000);

        oracle = new RiskOracle(oracleSigner);
    }

    function _makePayload(uint256 timestamp, uint256 nonce)
        internal
        view
        returns (IRiskOracle.RiskPayload memory)
    {
        return
            IRiskOracle.RiskPayload({
                user: user,
                score: 750,
                riskTier: 2,
                timestamp: timestamp == 0 ? block.timestamp : timestamp,
                nonce: nonce
            });
    }

    function _signPayload(IRiskOracle.RiskPayload memory payload, uint256 signerPrivateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = oracle.getPayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _makePayloadV2(uint64 timestamp, uint64 nonce)
        internal
        view
        returns (IRiskOracle.RiskPayloadV2 memory)
    {
        return
            IRiskOracle.RiskPayloadV2({
                user: user,
                score: 750,
                riskTier: 2,
                confidenceBps: 8200,
                modelId: keccak256("RISK_V2_2026_02_15"),
                reasonsHash: keccak256("reasons"),
                evidenceHash: keccak256("evidence"),
                timestamp: timestamp == 0 ? uint64(block.timestamp) : timestamp,
                nonce: nonce
            });
    }

    function _signPayloadV2(IRiskOracle.RiskPayloadV2 memory payload, uint256 signerPrivateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = oracle.getPayloadDigestV2(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // Valid signature
    // -------------------------------------------------------------------------

    function test_VerifyRiskPayload_ValidSignature() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(0, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        bool ok = oracle.verifyRiskPayload(payload, sig);
        assertTrue(ok);

        // Nonce should be consumed
        assertTrue(oracle.isNonceUsed(user, 0));
    }

    function test_VerifyRiskPayloadView_ValidSignature() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(0, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        bool ok = oracle.verifyRiskPayloadView(payload, sig);
        assertTrue(ok);
    }

    // -------------------------------------------------------------------------
    // Invalid signer
    // -------------------------------------------------------------------------

    function test_VerifyRiskPayload_InvalidSigner_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(0, 0);
        bytes memory sig = _signPayload(payload, WRONG_PRIVATE_KEY);

        vm.expectRevert(RiskOracle.RiskOracle_InvalidSignature.selector);
        oracle.verifyRiskPayload(payload, sig);
    }

    function test_VerifyRiskPayloadView_InvalidSigner_ReturnsFalse() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(0, 0);
        bytes memory sig = _signPayload(payload, WRONG_PRIVATE_KEY);

        bool ok = oracle.verifyRiskPayloadView(payload, sig);
        assertFalse(ok);
    }

    // -------------------------------------------------------------------------
    // Expired timestamp
    // -------------------------------------------------------------------------

    function test_VerifyRiskPayload_ExpiredTimestamp_Reverts() public {
        uint256 oldTimestamp = block.timestamp - 400; // 400s ago, > 300s window
        IRiskOracle.RiskPayload memory payload = _makePayload(oldTimestamp, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        vm.expectRevert(RiskOracle.RiskOracle_ExpiredTimestamp.selector);
        oracle.verifyRiskPayload(payload, sig);
    }

    function test_VerifyRiskPayloadView_ExpiredTimestamp_ReturnsFalse() public {
        uint256 oldTimestamp = block.timestamp - 400;
        IRiskOracle.RiskPayload memory payload = _makePayload(oldTimestamp, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        bool ok = oracle.verifyRiskPayloadView(payload, sig);
        assertFalse(ok);
    }

    function test_VerifyRiskPayload_AtValidityBoundary_Succeeds() public {
        uint256 boundaryTimestamp = block.timestamp - 300; // Exactly at edge
        IRiskOracle.RiskPayload memory payload = _makePayload(boundaryTimestamp, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        bool ok = oracle.verifyRiskPayload(payload, sig);
        assertTrue(ok);
    }

    function test_VerifyRiskPayload_JustPastValidity_Reverts() public {
        uint256 pastTimestamp = block.timestamp - 301;
        IRiskOracle.RiskPayload memory payload = _makePayload(pastTimestamp, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        vm.expectRevert(RiskOracle.RiskOracle_ExpiredTimestamp.selector);
        oracle.verifyRiskPayload(payload, sig);
    }

    // -------------------------------------------------------------------------
    // Replay attack prevention
    // -------------------------------------------------------------------------

    function test_VerifyRiskPayload_ReplayAttack_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(0, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        bool ok1 = oracle.verifyRiskPayload(payload, sig);
        assertTrue(ok1);

        vm.expectRevert(RiskOracle.RiskOracle_ReplayAttack.selector);
        oracle.verifyRiskPayload(payload, sig);
    }

    function test_VerifyRiskPayloadView_AfterConsume_ReturnsFalse() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(0, 0);
        bytes memory sig = _signPayload(payload, ORACLE_PRIVATE_KEY);

        oracle.verifyRiskPayload(payload, sig);

        bool ok = oracle.verifyRiskPayloadView(payload, sig);
        assertFalse(ok);
    }

    function test_VerifyRiskPayload_DifferentNonce_SameUser_Succeeds() public {
        IRiskOracle.RiskPayload memory payload1 = _makePayload(0, 0);
        IRiskOracle.RiskPayload memory payload2 = _makePayload(0, 1);

        bytes memory sig1 = _signPayload(payload1, ORACLE_PRIVATE_KEY);
        bytes memory sig2 = _signPayload(payload2, ORACLE_PRIVATE_KEY);

        assertTrue(oracle.verifyRiskPayload(payload1, sig1));
        assertTrue(oracle.verifyRiskPayload(payload2, sig2));
    }

    // -------------------------------------------------------------------------
    // Domain & digest
    // -------------------------------------------------------------------------

    function test_DomainSeparator_IsConsistent() public view {
        bytes32 ds = oracle.domainSeparator();
        assertNotEq(ds, bytes32(0));
    }

    function test_GetPayloadDigest_ChangesWithPayload() public view {
        IRiskOracle.RiskPayload memory p1 = _makePayload(0, 0);
        IRiskOracle.RiskPayload memory p2 = _makePayload(0, 1);

        bytes32 d1 = oracle.getPayloadDigest(p1);
        bytes32 d2 = oracle.getPayloadDigest(p2);

        assertNotEq(d1, d2);
    }

    // -------------------------------------------------------------------------
    // V2 payload path
    // -------------------------------------------------------------------------

    function test_VerifyRiskPayloadV2_ValidSignature() public {
        IRiskOracle.RiskPayloadV2 memory payload = _makePayloadV2(0, 0);
        bytes memory sig = _signPayloadV2(payload, ORACLE_PRIVATE_KEY);

        bool ok = oracle.verifyRiskPayloadV2(payload, sig);
        assertTrue(ok);
        assertTrue(oracle.isNonceUsed(user, 0));
    }

    function test_VerifyRiskPayloadV2_InvalidSigner_Reverts() public {
        IRiskOracle.RiskPayloadV2 memory payload = _makePayloadV2(0, 0);
        bytes memory sig = _signPayloadV2(payload, WRONG_PRIVATE_KEY);

        vm.expectRevert(RiskOracle.RiskOracle_InvalidSignature.selector);
        oracle.verifyRiskPayloadV2(payload, sig);
    }

    function test_VerifyRiskPayloadV2_Expired_Reverts() public {
        IRiskOracle.RiskPayloadV2 memory payload = _makePayloadV2(
            uint64(block.timestamp - 400),
            0
        );
        bytes memory sig = _signPayloadV2(payload, ORACLE_PRIVATE_KEY);
        vm.expectRevert(RiskOracle.RiskOracle_ExpiredTimestamp.selector);
        oracle.verifyRiskPayloadV2(payload, sig);
    }

    function test_VerifyRiskPayloadV2_Replay_Reverts() public {
        IRiskOracle.RiskPayloadV2 memory payload = _makePayloadV2(0, 0);
        bytes memory sig = _signPayloadV2(payload, ORACLE_PRIVATE_KEY);
        assertTrue(oracle.verifyRiskPayloadV2(payload, sig));

        vm.expectRevert(RiskOracle.RiskOracle_ReplayAttack.selector);
        oracle.verifyRiskPayloadV2(payload, sig);
    }

    function test_GetPayloadDigestV2_ChangesWithPayload() public view {
        IRiskOracle.RiskPayloadV2 memory p1 = _makePayloadV2(0, 0);
        IRiskOracle.RiskPayloadV2 memory p2 = _makePayloadV2(0, 1);
        bytes32 d1 = oracle.getPayloadDigestV2(p1);
        bytes32 d2 = oracle.getPayloadDigestV2(p2);
        assertNotEq(d1, d2);
    }
}
