// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {AttestationRegistry} from "../../src/AttestationRegistry.sol";
import {IAttestationRegistry} from "../../src/interfaces/IAttestationRegistry.sol";

contract AttestationKindActions {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant ISSUER_PK = 0xA11CE;
    address internal constant USER = address(0xBEEF);
    bytes32 internal constant SUBJECT_ID = keccak256("KIND_INVARIANT_SUBJECT");

    AttestationRegistry internal registry;
    bytes32[] public walletIds;
    bytes32[] public subjectIds;

    constructor(AttestationRegistry registry_) {
        registry = registry_;
    }

    function walletCount() external view returns (uint256) {
        return walletIds.length;
    }

    function subjectCount() external view returns (uint256) {
        return subjectIds.length;
    }

    function actSubmitWallet(bytes32 seed) external {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: USER,
            attestationType: keccak256("KYB_PASS"),
            dataHash: keccak256(abi.encode(seed, "wallet")),
            data: bytes32(0),
            uri: "ipfs://wallet-kind",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: registry.nextNonce(USER)
        });

        bytes32 digest = registry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, digest);
        bytes32 id = registry.submitAttestation(a, abi.encodePacked(r, s, v));
        walletIds.push(id);
    }

    function actSubmitSubject(bytes32 seed) external {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: SUBJECT_ID,
            attestationType: keccak256("DSCR_BPS"),
            dataHash: keccak256(abi.encode(seed, "subject")),
            data: bytes32(uint256(13_000)),
            uri: "ipfs://subject-kind",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: registry.nextSubjectNonce(SUBJECT_ID)
        });

        bytes32 digest = registry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, digest);
        bytes32 id = registry.submitSubjectAttestation(a, abi.encodePacked(r, s, v));
        subjectIds.push(id);
    }
}

contract InvariantAttestationKind is Test {
    uint8 internal constant KIND_WALLET = 1;
    uint8 internal constant KIND_SUBJECT = 2;
    uint256 internal constant MAX_IDS_PER_RUN = 8;

    AttestationRegistry internal registry;
    AttestationKindActions internal actions;

    function setUp() external {
        address admin = makeAddr("admin");
        address issuer = vm.addr(0xA11CE);

        registry = new AttestationRegistry(admin);
        vm.startPrank(admin);
        registry.grantRole(registry.ISSUER_ROLE(), issuer);
        vm.stopPrank();

        actions = new AttestationKindActions(registry);
        targetContract(address(actions));
    }

    function invariant_AttestationKindImmutableAndSeparated() external view {
        uint256 walletCount = actions.walletCount();
        uint256 walletChecks = walletCount > MAX_IDS_PER_RUN ? MAX_IDS_PER_RUN : walletCount;
        for (uint256 i = 0; i < walletChecks; i++) {
            bytes32 id = actions.walletIds(i);
            assertEq(uint8(registry.kindOf(id)), KIND_WALLET);
        }

        uint256 subjectCount = actions.subjectCount();
        uint256 subjectChecks = subjectCount > MAX_IDS_PER_RUN ? MAX_IDS_PER_RUN : subjectCount;
        for (uint256 i = 0; i < subjectChecks; i++) {
            bytes32 id = actions.subjectIds(i);
            assertEq(uint8(registry.kindOf(id)), KIND_SUBJECT);
        }
    }
}
