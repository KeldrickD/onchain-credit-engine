// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {RiskOracle} from "../../src/RiskOracle.sol";
import {CreditRegistry} from "../../src/CreditRegistry.sol";

import {IRiskOracle} from "../../src/interfaces/IRiskOracle.sol";
import {ICreditRegistry} from "../../src/interfaces/ICreditRegistry.sol";

contract CreditLaneActions {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant ORACLE_PK = 0xA11CE;
    address internal constant WALLET = address(0xBEEF);
    bytes32 internal constant SUBJECT_KEY = keccak256("INVARIANT_KEYED_PROFILE");

    RiskOracle internal riskOracle;
    CreditRegistry internal creditRegistry;

    bool public keyedMutatedDuringWalletWrite;
    bool public walletMutatedDuringKeyWrite;

    constructor(RiskOracle riskOracle_, CreditRegistry creditRegistry_) {
        riskOracle = riskOracle_;
        creditRegistry = creditRegistry_;
    }

    function actCommitWallet(uint16 scoreSeed) external {
        bytes32 keyHashBefore = _profileHash(creditRegistry.getProfile(SUBJECT_KEY));
        uint16 score = uint16(uint256(scoreSeed) % 1001);

        IRiskOracle.RiskPayloadV2 memory p = IRiskOracle.RiskPayloadV2({
            user: WALLET,
            score: score,
            riskTier: uint8(score % 4),
            confidenceBps: 6000,
            modelId: keccak256("LANE_WALLET"),
            reasonsHash: keccak256("wallet_reasons"),
            evidenceHash: keccak256("wallet_evidence"),
            timestamp: uint64(block.timestamp),
            nonce: uint64(riskOracle.nextNonce(WALLET))
        });

        bytes32 digest = riskOracle.getPayloadDigestV2(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        creditRegistry.updateCreditProfileV2(p, abi.encodePacked(r, s, v));

        bytes32 keyHashAfter = _profileHash(creditRegistry.getProfile(SUBJECT_KEY));
        if (keyHashAfter != keyHashBefore) keyedMutatedDuringWalletWrite = true;
    }

    function actCommitByKey(uint16 scoreSeed) external {
        bytes32 walletHashBefore = _profileHash(creditRegistry.getCreditProfile(WALLET));
        uint16 score = uint16(uint256(scoreSeed) % 1001);

        IRiskOracle.RiskPayloadV2ByKey memory p = IRiskOracle.RiskPayloadV2ByKey({
            subjectKey: SUBJECT_KEY,
            score: score,
            riskTier: uint8(score % 4),
            confidenceBps: 6000,
            modelId: keccak256("LANE_KEY"),
            reasonsHash: keccak256("key_reasons"),
            evidenceHash: keccak256("key_evidence"),
            timestamp: uint64(block.timestamp),
            nonce: riskOracle.nextNonceKey(SUBJECT_KEY)
        });

        bytes32 digest = riskOracle.getPayloadDigestV2ByKey(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_PK, digest);
        creditRegistry.updateCreditProfileV2ByKey(p, abi.encodePacked(r, s, v));

        bytes32 walletHashAfter = _profileHash(creditRegistry.getCreditProfile(WALLET));
        if (walletHashAfter != walletHashBefore) walletMutatedDuringKeyWrite = true;
    }

    function _profileHash(ICreditRegistry.CreditProfile memory p) internal pure returns (bytes32) {
        return abi.encode(p).length == 0 ? bytes32(0) : keccak256(abi.encode(p));
    }
}

contract InvariantCreditLaneSeparation is Test {
    RiskOracle internal riskOracle;
    CreditRegistry internal creditRegistry;
    CreditLaneActions internal actions;

    function setUp() external {
        riskOracle = new RiskOracle(vm.addr(0xA11CE));
        creditRegistry = new CreditRegistry(address(riskOracle));

        actions = new CreditLaneActions(riskOracle, creditRegistry);
        targetContract(address(actions));
    }

    function invariant_WalletAndKeyedLanesNeverOverlap() external view {
        assertFalse(actions.keyedMutatedDuringWalletWrite());
        assertFalse(actions.walletMutatedDuringKeyWrite());
    }
}
