// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";

contract AttestationRegistrySubjectTest is Test {
    AttestationRegistry public registry;

    uint256 public constant ISSUER_KEY = 0xA11CE;
    uint256 public constant OTHER_KEY = 0xB0B;
    address public issuer;
    address public otherSigner;
    address public admin;
    bytes32 public subjectId;

    bytes32 public constant NOI_TYPE = keccak256("DEAL_NOI_USD6");
    bytes32 public constant DSCR_TYPE = keccak256("DEAL_DSCR_BPS");

    function setUp() public {
        admin = makeAddr("admin");
        issuer = vm.addr(ISSUER_KEY);
        otherSigner = vm.addr(OTHER_KEY);
        subjectId = keccak256("DEAL:123");
        vm.warp(1000);

        registry = new AttestationRegistry(admin);
        bytes32 issuerRole = registry.ISSUER_ROLE();
        vm.prank(admin);
        registry.grantRole(issuerRole, issuer);
    }

    function _makeSubjectAttestation(
        bytes32 subj,
        bytes32 aType,
        bytes32 dataHash,
        bytes32 data,
        string memory uri,
        uint64 issuedAt,
        uint64 expiresAt,
        uint64 nonce
    ) internal view returns (IAttestationRegistry.SubjectAttestation memory) {
        return IAttestationRegistry.SubjectAttestation({
            subjectId: subj,
            attestationType: aType,
            dataHash: dataHash,
            data: data,
            uri: uri,
            issuedAt: issuedAt == 0 ? uint64(block.timestamp) : issuedAt,
            expiresAt: expiresAt,
            nonce: nonce
        });
    }

    function _signSubjectAttestation(IAttestationRegistry.SubjectAttestation memory a, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = registry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_SubmitSubjectAttestation_ValidSignature_Accepted() public {
        IAttestationRegistry.SubjectAttestation memory a = _makeSubjectAttestation(
            subjectId, NOI_TYPE, keccak256("noi"), bytes32(uint256(120_000_000)), "ipfs://deal", 0, 0, 0
        );
        bytes32 id = registry.submitSubjectAttestation(a, _signSubjectAttestation(a, ISSUER_KEY));
        assertNotEq(id, bytes32(0));

        (IAttestationRegistry.StoredSubjectAttestation memory att, bool revoked, bool expired) =
            registry.getSubjectAttestation(id);
        assertEq(att.subjectId, subjectId);
        assertEq(att.attestationType, NOI_TYPE);
        assertEq(att.dataHash, keccak256("noi"));
        assertEq(att.issuer, issuer);
        assertFalse(revoked);
        assertFalse(expired);
        assertEq(registry.nextSubjectNonce(subjectId), 1);
        assertTrue(registry.isValid(id));
    }

    function test_SubmitSubjectAttestation_SequentialNonces_Succeeds() public {
        for (uint64 i = 0; i < 3; i++) {
            IAttestationRegistry.SubjectAttestation memory a =
                _makeSubjectAttestation(subjectId, DSCR_TYPE, bytes32(uint256(i)), bytes32(uint256(13_000 + i)), "", 0, 0, i);
            registry.submitSubjectAttestation(a, _signSubjectAttestation(a, ISSUER_KEY));
        }
        assertEq(registry.nextSubjectNonce(subjectId), 3);
    }

    function test_SubmitSubjectAttestation_InvalidNonce_Reverts() public {
        IAttestationRegistry.SubjectAttestation memory a =
            _makeSubjectAttestation(subjectId, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 5);
        bytes memory sig = _signSubjectAttestation(a, ISSUER_KEY);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_InvalidNonce.selector);
        registry.submitSubjectAttestation(a, sig);
    }

    function test_SubmitSubjectAttestation_IssuerNotAllowed_Reverts() public {
        IAttestationRegistry.SubjectAttestation memory a =
            _makeSubjectAttestation(subjectId, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes memory sig = _signSubjectAttestation(a, OTHER_KEY);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_IssuerNotAllowed.selector);
        registry.submitSubjectAttestation(a, sig);
    }

    function test_SubmitSubjectAttestation_ExpiryAndRevocation() public {
        uint64 issuedAt = uint64(block.timestamp);
        uint64 expiresAt = issuedAt + 3600;
        IAttestationRegistry.SubjectAttestation memory a =
            _makeSubjectAttestation(subjectId, NOI_TYPE, keccak256("x"), bytes32(0), "", issuedAt, expiresAt, 0);
        bytes32 id = registry.submitSubjectAttestation(a, _signSubjectAttestation(a, ISSUER_KEY));
        assertTrue(registry.isValid(id));

        vm.warp(issuedAt + 3601);
        assertFalse(registry.isValid(id));

        IAttestationRegistry.SubjectAttestation memory b =
            _makeSubjectAttestation(subjectId, NOI_TYPE, keccak256("y"), bytes32(0), "", 0, 0, 1);
        bytes32 id2 = registry.submitSubjectAttestation(b, _signSubjectAttestation(b, ISSUER_KEY));
        assertTrue(registry.isValid(id2));

        vm.prank(issuer);
        registry.revoke(id2);
        assertFalse(registry.isValid(id2));
    }

    function test_GetLatestSubject_ReturnsMostRecentByType() public {
        IAttestationRegistry.SubjectAttestation memory a1 =
            _makeSubjectAttestation(subjectId, DSCR_TYPE, keccak256("a"), bytes32(uint256(12_000)), "", 0, 0, 0);
        IAttestationRegistry.SubjectAttestation memory a2 =
            _makeSubjectAttestation(subjectId, DSCR_TYPE, keccak256("b"), bytes32(uint256(13_000)), "", 0, 0, 1);

        bytes32 id1 = registry.submitSubjectAttestation(a1, _signSubjectAttestation(a1, ISSUER_KEY));
        bytes32 id2 = registry.submitSubjectAttestation(a2, _signSubjectAttestation(a2, ISSUER_KEY));
        assertNotEq(id1, id2);

        bytes32 latestId = registry.getLatestSubjectAttestationId(subjectId, DSCR_TYPE);
        assertEq(latestId, id2);

        (IAttestationRegistry.StoredSubjectAttestation memory latest,,) = registry.getLatestSubject(subjectId, DSCR_TYPE);
        assertEq(latest.dataHash, keccak256("b"));
        assertEq(uint256(latest.data), 13_000);
    }
}
