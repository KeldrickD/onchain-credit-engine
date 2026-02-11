// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CreditRegistry} from "../src/CreditRegistry.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {ICreditRegistry} from "../src/interfaces/ICreditRegistry.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";

contract CreditRegistryTest is Test {
    event CreditProfileUpdated(
        address indexed user,
        uint256 score,
        uint256 riskTier,
        uint256 timestamp,
        uint256 nonce
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

    // -------------------------------------------------------------------------
    // Successful update
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_Success_WritesProfile() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 750, 2, 1);
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);

        ICreditRegistry.CreditProfile memory profile = registry.getCreditProfile(user);
        assertEq(profile.score, 750);
        assertEq(profile.riskTier, 2);
        assertEq(profile.lastUpdated, block.timestamp);
    }

    function test_UpdateCreditProfile_LastUpdated_EqualsBlockTimestamp() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 800, 1, 1);
        bytes memory sig = _signPayload(payload);

        uint256 beforeTs = block.timestamp;
        registry.updateCreditProfile(payload, sig);
        uint256 afterTs = block.timestamp;

        ICreditRegistry.CreditProfile memory profile = registry.getCreditProfile(user);
        assertGe(profile.lastUpdated, beforeTs);
        assertLe(profile.lastUpdated, afterTs);
    }

    function test_UpdateCreditProfile_EmitsEvent() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 600, 3, 1);
        bytes memory sig = _signPayload(payload);

        vm.expectEmit(true, true, true, true);
        emit CreditProfileUpdated(user, 600, 3, payload.timestamp, 1);

        registry.updateCreditProfile(payload, sig);
    }

    // -------------------------------------------------------------------------
    // Score bounds
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_ScoreOutOfRange_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 1001, 2, 1);
        bytes memory sig = _signPayload(payload);

        vm.expectRevert(CreditRegistry.CreditRegistry_ScoreOutOfRange.selector);
        registry.updateCreditProfile(payload, sig);
    }

    function test_UpdateCreditProfile_ScoreAtMax_Succeeds() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 1000, 0, 1);
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);
        assertEq(registry.getCreditProfile(user).score, 1000);
    }

    // -------------------------------------------------------------------------
    // Tier bounds
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_InvalidTier_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 750, 6, 1);
        bytes memory sig = _signPayload(payload);

        vm.expectRevert(CreditRegistry.CreditRegistry_InvalidTier.selector);
        registry.updateCreditProfile(payload, sig);
    }

    function test_UpdateCreditProfile_TierAtMax_Succeeds() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 500, 5, 1);
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);
        assertEq(registry.getCreditProfile(user).riskTier, 5);
    }

    // -------------------------------------------------------------------------
    // Replay at registry level
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_CannotReuseSameSignature_Reverts() public {
        IRiskOracle.RiskPayload memory payload = _makePayload(user, 750, 2, 1);
        bytes memory sig = _signPayload(payload);

        registry.updateCreditProfile(payload, sig);

        vm.expectRevert(RiskOracle.RiskOracle_ReplayAttack.selector);
        registry.updateCreditProfile(payload, sig);
    }

    // -------------------------------------------------------------------------
    // Different users independent
    // -------------------------------------------------------------------------

    function test_UpdateCreditProfile_DifferentUsers_Independent() public {
        IRiskOracle.RiskPayload memory payload1 = _makePayload(user, 700, 1, 1);
        IRiskOracle.RiskPayload memory payload2 = _makePayload(user2, 900, 0, 1);

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
        IRiskOracle.RiskPayload memory payload1 = _makePayload(user, 600, 2, 1);
        IRiskOracle.RiskPayload memory payload2 = _makePayload(user, 850, 1, 2);

        registry.updateCreditProfile(payload1, _signPayload(payload1));
        registry.updateCreditProfile(payload2, _signPayload(payload2));

        ICreditRegistry.CreditProfile memory profile = registry.getCreditProfile(user);
        assertEq(profile.score, 850);
        assertEq(profile.riskTier, 1);
    }
}
