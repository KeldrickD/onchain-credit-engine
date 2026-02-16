// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {ICreditRegistry} from "../src/interfaces/ICreditRegistry.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";

contract CreditRegistryTest is Test {
    event CreditProfileUpdated(address indexed user, uint256 score, uint256 riskTier, uint256 timestamp, uint256 nonce);
    event CreditProfileUpdatedV2(
        address indexed user,
        uint16 score,
        uint8 riskTier,
        uint16 confidenceBps,
        bytes32 modelId,
        bytes32 reasonsHash,
        bytes32 evidenceHash,
        uint64 timestamp,
        uint64 nonce
    );
    CreditRegistry public registry;
    RiskOracle public oracle;

    uint256 public constant ORACLE_PRIVATE_KEY = 0xA11CE;
    address public oracleSigner;
    address public user;
    address public user2;

    function setUp() public {
        oracleSigner = vm.addr(ORACLE_PRIVATE_KEY);
        user = makeAddr("user");
        user2 = makeAddr("user2");

        oracle = new RiskOracle(oracleSigner);
        registry = new CreditRegistry(address(oracle));
    }

    function _makePayload(address targetUser, uint256 score, uint256 riskTier, uint256 nonce)
        internal
        view
        returns (IRiskOracle.RiskPayload memory)
    {
        return
            IRiskOracle.RiskPayload({
                user: targetUser,
                score: score,
                riskTier: riskTier,
                timestamp: block.timestamp,
                nonce: nonce
            });
    }

    function _signPayload(IRiskOracle.RiskPayload memory payload) internal view returns (bytes memory) {
        bytes32 digest = oracle.getPayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _makePayloadV2(
        address targetUser,
        uint16 score,
        uint8 riskTier,
        uint16 confidenceBps,
        bytes32 modelId,
        bytes32 reasonsHash,
        bytes32 evidenceHash,
        uint64 nonce
    ) internal view returns (IRiskOracle.RiskPayloadV2 memory) {
        return
            IRiskOracle.RiskPayloadV2({
                user: targetUser,
                score: score,
                riskTier: riskTier,
                confidenceBps: confidenceBps,
                modelId: modelId,
                reasonsHash: reasonsHash,
                evidenceHash: evidenceHash,
                timestamp: uint64(block.timestamp),
                nonce: nonce
            });
    }

    function _signPayloadV2(IRiskOracle.RiskPayloadV2 memory payload) internal view returns (bytes memory) {
        bytes32 digest = oracle.getPayloadDigestV2(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // Successful update
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_Success_WritesProfile() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 750, 2, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);

        ICreditRegistry.CreditProfile memory profile = registry.getCreditProfile(user);
        assertEq(profile.score, 750);
        assertEq(profile.riskTier, 2);
        assertEq(profile.lastUpdated, block.timestamp);
        assertEq(profile.modelId, bytes32(0));
        assertEq(profile.confidenceBps, 0);
    }

    function test_UpdateCreditProfile_EmitsEvent() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 600, 3, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        vm.expectEmit(true, true, true, true);
        emit CreditProfileUpdated(user, 600, 3, payload.timestamp, 1);

        registry.updateCreditProfile(payload, sig);
    }

    // -------------------------------------------------------------------------
    // Score bounds
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_ScoreOutOfRange_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 1001, 2, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        vm.expectRevert(CreditRegistry.CreditRegistry_ScoreOutOfRange.selector);
        registry.updateCreditProfile(payload, sig);
    }

    function test_UpdateCreditProfile_ScoreAtMax_Succeeds() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 1000, 0, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);
        assertEq(registry.getCreditProfile(user).score, 1000);
    }

    // -------------------------------------------------------------------------
    // Tier bounds
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_InvalidTier_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 750, 6, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        vm.expectRevert(CreditRegistry.CreditRegistry_InvalidTier.selector);
        registry.updateCreditProfile(payload, sig);
    }

    function test_UpdateCreditProfile_TierAtMax_Succeeds() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 500, 5, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);
        assertEq(registry.getCreditProfile(user).riskTier, 5);
    }

    // -------------------------------------------------------------------------
    // Replay at registry level
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_CannotReuseSameSignature_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 750, 2, oracle.nextNonce(user));
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);

        vm.expectRevert(RiskOracle.RiskOracle_ReplayAttack.selector);
        registry.updateCreditProfile(payload, sig);
    }

    // -------------------------------------------------------------------------
    // Different users independent
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_DifferentUsers_Independent() public {
        IRiskOracle.RiskPayload memory payload1 = _makePayload(user, 700, 1, oracle.nextNonce(user));
        IRiskOracle.RiskPayload memory payload2 = _makePayload(user2, 900, 0, oracle.nextNonce(user2));

        registry.updateCreditProfile(payload1, _signPayload(payload1));
        registry.updateCreditProfile(payload2, _signPayload(payload2));

        ICreditRegistry.CreditProfile memory p1 = registry.getCreditProfile(user);
        ICreditRegistry.CreditProfile memory p2 = registry.getCreditProfile(user2);

        assertEq(p1.score, 700);
        assertEq(p1.riskTier, 1);
        assertEq(p2.score, 900);
        assertEq(p2.riskTier, 0);
    }

    function test_UpdateCreditProfile_SameUser_NewNonce_Overwrites() public {
        IRiskOracle.RiskPayload memory payload1 = _makePayload(user, 600, 2, oracle.nextNonce(user));
        IRiskOracle.RiskPayload memory payload2 = _makePayload(user, 850, 1, oracle.nextNonce(user) + 1);

        registry.updateCreditProfile(payload1, _signPayload(payload1));
        registry.updateCreditProfile(payload2, _signPayload(payload2));

        ICreditRegistry.CreditProfile memory profile = registry.getCreditProfile(user);
        assertEq(profile.score, 850);
        assertEq(profile.riskTier, 1);
    }

    // -------------------------------------------------------------------------
    // V2 update flow
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfileV2_WritesMetadata_AndEmits() public {
        bytes32 modelId = keccak256("RISK_V2_2026_02_15");
        bytes32 reasonsHash = keccak256("reasons");
        bytes32 evidenceHash = keccak256("evidence");
        IRiskOracle.RiskPayloadV2 memory payload = _makePayloadV2(
            user,
            790,
            2,
            8400,
            modelId,
            reasonsHash,
            evidenceHash,
            uint64(oracle.nextNonce(user))
        );
        bytes memory sig = _signPayloadV2(payload);

        vm.expectEmit(true, true, true, true);
        emit CreditProfileUpdatedV2(
            user,
            790,
            2,
            8400,
            modelId,
            reasonsHash,
            evidenceHash,
            payload.timestamp,
            payload.nonce
        );
        registry.updateCreditProfileV2(payload, sig);

        ICreditRegistry.CreditProfile memory profile = registry.getCreditProfile(user);
        assertEq(profile.score, 790);
        assertEq(profile.riskTier, 2);
        assertEq(profile.confidenceBps, 8400);
        assertEq(profile.modelId, modelId);
        assertEq(profile.reasonsHash, reasonsHash);
        assertEq(profile.evidenceHash, evidenceHash);
    }

    function test_UpdateCreditProfileV2_ReplayFails() public {
        IRiskOracle.RiskPayloadV2 memory payload = _makePayloadV2(
            user,
            700,
            1,
            5000,
            keccak256("m"),
            keccak256("r"),
            keccak256("e"),
            uint64(oracle.nextNonce(user))
        );
        bytes memory sig = _signPayloadV2(payload);
        registry.updateCreditProfileV2(payload, sig);

        vm.expectRevert(RiskOracle.RiskOracle_ReplayAttack.selector);
        registry.updateCreditProfileV2(payload, sig);
    }
}
