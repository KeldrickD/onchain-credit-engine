// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";

contract AttestationRegistryTrustedTest is Test {
    AttestationRegistry internal attestationRegistry;
    IssuerRegistry internal issuerRegistry;

    uint256 internal constant ISSUER1_PK = 0xA11CE;
    uint256 internal constant ISSUER2_PK = 0xB0B;
    address internal issuer1;
    address internal issuer2;
    address internal admin;
    bytes32 internal constant DSCR_BPS = keccak256("DSCR_BPS");

    function setUp() public {
        admin = makeAddr("admin");
        issuer1 = vm.addr(ISSUER1_PK);
        issuer2 = vm.addr(ISSUER2_PK);

        attestationRegistry = new AttestationRegistry(admin);
        issuerRegistry = new IssuerRegistry(admin);

        vm.startPrank(admin);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuer1);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuer2);
        attestationRegistry.setIssuerRegistry(address(issuerRegistry));

        issuerRegistry.setIssuer(issuer1, true, 9000, bytes32(0), "ipfs://issuer1");
        issuerRegistry.setIssuer(issuer2, true, 3000, bytes32(0), "ipfs://issuer2");
        issuerRegistry.setIssuerTypePermission(issuer1, DSCR_BPS, true);
        issuerRegistry.setIssuerTypePermission(issuer2, DSCR_BPS, true);
        issuerRegistry.setMinTrustScoreBpsForType(DSCR_BPS, 7000);
        vm.stopPrank();
    }

    function _submitWalletDscr(address subject, uint256 issuerPk, bytes32 dataHash) internal returns (bytes32 id) {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: subject,
            attestationType: DSCR_BPS,
            dataHash: dataHash,
            data: bytes32(uint256(13_000)),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextNonce(subject)
        });
        bytes32 digest = attestationRegistry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        return attestationRegistry.submitAttestation(a, abi.encodePacked(r, s, v));
    }

    function _submitSubjectDscr(bytes32 subjectId, uint256 issuerPk, bytes32 dataHash) internal returns (bytes32 id) {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: subjectId,
            attestationType: DSCR_BPS,
            dataHash: dataHash,
            data: bytes32(uint256(13_000)),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextSubjectNonce(subjectId)
        });
        bytes32 digest = attestationRegistry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        return attestationRegistry.submitSubjectAttestation(a, abi.encodePacked(r, s, v));
    }

    function test_UnsetRegistryReturnsFalse() public {
        vm.prank(admin);
        attestationRegistry.setIssuerRegistry(address(0));

        bytes32 id = _submitWalletDscr(makeAddr("wallet-subject"), ISSUER1_PK, keccak256("w1"));
        assertFalse(attestationRegistry.isTrustedIssuerForAttestation(id));
    }

    function test_UnknownAttestationIdReturnsFalse() public view {
        assertFalse(attestationRegistry.isTrustedIssuerForAttestation(keccak256("nope")));
    }

    function test_WalletAttestationTrustedVsUntrusted() public {
        bytes32 id1 = _submitWalletDscr(makeAddr("wallet-subject"), ISSUER1_PK, keccak256("w-high"));
        bytes32 id2 = _submitWalletDscr(makeAddr("wallet-subject"), ISSUER2_PK, keccak256("w-low"));

        assertTrue(attestationRegistry.isTrustedIssuerForAttestation(id1));
        assertFalse(attestationRegistry.isTrustedIssuerForAttestation(id2));
    }

    function test_SubjectAttestationTrustedVsUntrusted() public {
        bytes32 subjectId = keccak256("subject:1");
        bytes32 id1 = _submitSubjectDscr(subjectId, ISSUER1_PK, keccak256("s-high"));
        bytes32 id2 = _submitSubjectDscr(subjectId, ISSUER2_PK, keccak256("s-low"));

        assertTrue(attestationRegistry.isTrustedIssuerForAttestation(id1));
        assertFalse(attestationRegistry.isTrustedIssuerForAttestation(id2));
    }

    function test_PermissionRemovedFlipsTrust() public {
        bytes32 id1 = _submitWalletDscr(makeAddr("wallet-subject"), ISSUER1_PK, keccak256("w-high"));
        assertTrue(attestationRegistry.isTrustedIssuerForAttestation(id1));

        vm.prank(admin);
        issuerRegistry.setIssuerTypePermission(issuer1, DSCR_BPS, false);

        assertFalse(attestationRegistry.isTrustedIssuerForAttestation(id1));
    }

    function test_MinTrustRaisedFlipsTrust() public {
        bytes32 id1 = _submitWalletDscr(makeAddr("wallet-subject"), ISSUER1_PK, keccak256("w-high"));
        assertTrue(attestationRegistry.isTrustedIssuerForAttestation(id1));

        vm.prank(admin);
        issuerRegistry.setMinTrustScoreBpsForType(DSCR_BPS, 9500);

        assertFalse(attestationRegistry.isTrustedIssuerForAttestation(id1));
    }
}
