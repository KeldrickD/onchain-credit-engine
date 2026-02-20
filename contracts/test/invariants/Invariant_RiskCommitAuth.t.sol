// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RiskOracle} from "../../src/RiskOracle.sol";
import {CreditRegistry} from "../../src/CreditRegistry.sol";
import {IRiskOracle} from "../../src/interfaces/IRiskOracle.sol";

contract InvariantRiskCommitAuth is Test {
    uint256 internal constant ORACLE_PK = 0xA11CE;
    uint256 internal constant WRONG_PK = 0x1234;

    address internal user;
    bytes32 internal subjectKey;

    RiskOracle internal riskOracle;
    CreditRegistry internal creditRegistry;

    function setUp() external {
        riskOracle = new RiskOracle(vm.addr(ORACLE_PK));
        creditRegistry = new CreditRegistry(address(riskOracle));

        user = address(0xBEEF);
        subjectKey = keccak256("AUTH_INVARIANT_SUBJECT");
    }

    function testFuzz_NoCommitWithoutValidSig_Wallet(uint16 scoreSeed) external {
        uint16 score = uint16(uint256(scoreSeed) % 1001);
        IRiskOracle.RiskPayloadV2 memory p = IRiskOracle.RiskPayloadV2({
            user: user,
            score: score,
            riskTier: uint8(score % 4),
            confidenceBps: 5000,
            modelId: bytes32("MODEL"),
            reasonsHash: bytes32(0),
            evidenceHash: bytes32(0),
            timestamp: uint64(block.timestamp),
            nonce: uint64(riskOracle.nextNonce(user))
        });

        bytes32 digest = riskOracle.getPayloadDigestV2(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(WRONG_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(RiskOracle.RiskOracle_InvalidSignature.selector);
        creditRegistry.updateCreditProfileV2(p, sig);
    }

    function testFuzz_NoCommitWithoutValidSig_Keyed(uint16 scoreSeed) external {
        uint16 score = uint16(uint256(scoreSeed) % 1001);
        IRiskOracle.RiskPayloadV2ByKey memory p = IRiskOracle.RiskPayloadV2ByKey({
            subjectKey: subjectKey,
            score: score,
            riskTier: uint8(score % 4),
            confidenceBps: 5000,
            modelId: bytes32("MODEL"),
            reasonsHash: bytes32(0),
            evidenceHash: bytes32(0),
            timestamp: uint64(block.timestamp),
            nonce: riskOracle.nextNonceKey(subjectKey)
        });

        bytes32 digest = riskOracle.getPayloadDigestV2ByKey(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(WRONG_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(RiskOracle.RiskOracle_InvalidSignature.selector);
        creditRegistry.updateCreditProfileV2ByKey(p, sig);
    }
}
