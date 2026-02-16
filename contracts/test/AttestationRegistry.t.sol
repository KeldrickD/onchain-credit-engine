// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";

contract AttestationRegistryTest is Test {
    AttestationRegistry public registry;

    uint256 public constant ISSUER_KEY = 0xA11CE;
    uint256 public constant OTHER_KEY = 0xB0B;
    address public issuer;
    address public otherSigner;
    address public admin;
    address public subject;

    bytes32 public constant NOI_TYPE = keccak256("NOI_USD6");
    bytes32 public constant DSCR_TYPE = keccak256("DSCR_BPS");
    bytes32 public constant KYB_TYPE = keccak256("KYB_PASS");

    function setUp() public {
        admin = makeAddr("admin");
        issuer = vm.addr(ISSUER_KEY);
        otherSigner = vm.addr(OTHER_KEY);
        subject = makeAddr("subject");

        vm.warp(1000);

        registry = new AttestationRegistry(admin);
        vm.prank(admin);
        registry.grantRole(registry.ISSUER_ROLE(), issuer);
    }

    function _makeAttestation(
        address subj,
        bytes32 aType,
        bytes32 dataHash,
        bytes32 data,
        string memory uri,
        uint64 issuedAt,
        uint64 expiresAt,
        uint64 nonce
    ) internal view returns (IAttestationRegistry.Attestation memory) {
        return
            IAttestationRegistry.Attestation({
                subject: subj,
                attestationType: aType,
                dataHash: dataHash,
                data: data,
                uri: uri,
                issuedAt: issuedAt == 0 ? uint64(block.timestamp) : issuedAt,
                expiresAt: expiresAt,
                nonce: nonce
            });
    }

    function _signAttestation(IAttestationRegistry.Attestation memory a, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = registry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // Valid submission
    // -------------------------------------------------------------------------

    function test_SubmitAttestation_ValidSignature_Accepted() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("123"), bytes32(0), "ipfs://x", 0, 0, 0);
        bytes memory sig = _signAttestation(a, ISSUER_KEY);

        bytes32 id = registry.submitAttestation(a, sig);
        assertNotEq(id, bytes32(0));

        (IAttestationRegistry.StoredAttestation memory att, bool revoked, bool expired) =
            registry.getAttestation(id);
        assertEq(att.subject, subject);
        assertEq(att.attestationType, NOI_TYPE);
        assertEq(att.dataHash, keccak256("123"));
        assertEq(att.uri, "ipfs://x");
        assertEq(att.issuer, issuer);
        assertFalse(revoked);
        assertFalse(expired);
        assertTrue(registry.isValid(id));
        assertEq(registry.nextNonce(subject), 1);
    }

    function test_SubmitAttestation_LatestPointerUpdates() public {
        IAttestationRegistry.Attestation memory a1 =
            _makeAttestation(subject, NOI_TYPE, keccak256("1"), bytes32(0), "", 0, 0, 0);
        bytes memory sig1 = _signAttestation(a1, ISSUER_KEY);
        bytes32 id1 = registry.submitAttestation(a1, sig1);

        IAttestationRegistry.Attestation memory a2 =
            _makeAttestation(subject, NOI_TYPE, keccak256("2"), bytes32(0), "ipfs://y", 0, 0, 1);
        bytes memory sig2 = _signAttestation(a2, ISSUER_KEY);
        bytes32 id2 = registry.submitAttestation(a2, sig2);

        (IAttestationRegistry.StoredAttestation memory latest,,) =
            registry.getLatest(subject, NOI_TYPE);
        assertEq(latest.dataHash, keccak256("2"));
        assertEq(latest.issuer, issuer);
        assertNotEq(id1, id2);
    }

    function test_SubmitAttestation_DifferentTypes_SameSubject() public {
        IAttestationRegistry.Attestation memory aNoi =
            _makeAttestation(subject, NOI_TYPE, keccak256("noi"), bytes32(0), "", 0, 0, 0);
        IAttestationRegistry.Attestation memory aDscr =
            _makeAttestation(subject, DSCR_TYPE, keccak256("dscr"), bytes32(0), "", 0, 0, 0);

        bytes32 idNoi = registry.submitAttestation(aNoi, _signAttestation(aNoi, ISSUER_KEY));
        bytes32 idDscr = registry.submitAttestation(aDscr, _signAttestation(aDscr, ISSUER_KEY));

        assertNotEq(idNoi, idDscr);
        (IAttestationRegistry.StoredAttestation memory noi,,) = registry.getLatest(subject, NOI_TYPE);
        (IAttestationRegistry.StoredAttestation memory dscr,,) =
            registry.getLatest(subject, DSCR_TYPE);
        assertEq(noi.dataHash, keccak256("noi"));
        assertEq(dscr.dataHash, keccak256("dscr"));
    }

    // -------------------------------------------------------------------------
    // Issuer not allowed
    // -------------------------------------------------------------------------

    function test_SubmitAttestation_IssuerNotAllowed_Reverts() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes memory sig = _signAttestation(a, OTHER_KEY);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_IssuerNotAllowed.selector);
        registry.submitAttestation(a, sig);
    }

    // -------------------------------------------------------------------------
    // Replay nonce
    // -------------------------------------------------------------------------

    function test_SubmitAttestation_InvalidNonce_Reverts() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 5);
        bytes memory sig = _signAttestation(a, ISSUER_KEY);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_InvalidNonce.selector);
        registry.submitAttestation(a, sig);
    }

    function test_SubmitAttestation_ReplayNonce_AfterSubmit_Reverts() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes memory sig = _signAttestation(a, ISSUER_KEY);
        registry.submitAttestation(a, sig);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_InvalidNonce.selector);
        registry.submitAttestation(a, sig);
    }

    function test_SubmitAttestation_SequentialNonces_Succeeds() public {
        for (uint64 i = 0; i < 3; i++) {
            IAttestationRegistry.Attestation memory a =
                _makeAttestation(subject, NOI_TYPE, bytes32(uint256(i)), bytes32(0), "", 0, 0, i);
            bytes memory sig = _signAttestation(a, ISSUER_KEY);
            registry.submitAttestation(a, sig);
        }
        assertEq(registry.nextNonce(subject), 3);
    }

    // -------------------------------------------------------------------------
    // Revocation
    // -------------------------------------------------------------------------

    function test_Revoke_IssuerCanRevoke() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes32 id = registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));
        assertTrue(registry.isValid(id));

        vm.prank(issuer);
        registry.revoke(id);

        assertFalse(registry.isValid(id));
        (, bool revoked,) = registry.getAttestation(id);
        assertTrue(revoked);
    }

    function test_Revoke_AdminCanRevoke() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes32 id = registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));

        vm.prank(admin);
        registry.revoke(id);

        assertFalse(registry.isValid(id));
    }

    function test_Revoke_OtherCannotRevoke() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes32 id = registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));

        vm.prank(otherSigner);
        vm.expectRevert(IAttestationRegistry.AttestationRegistry_NotRevocable.selector);
        registry.revoke(id);
    }

    function test_Revoke_AlreadyRevoked_Reverts() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes32 id = registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));

        vm.prank(issuer);
        registry.revoke(id);

        vm.prank(issuer);
        vm.expectRevert(IAttestationRegistry.AttestationRegistry_AlreadyRevoked.selector);
        registry.revoke(id);
    }

    // -------------------------------------------------------------------------
    // Expiry
    // -------------------------------------------------------------------------

    function test_IsValid_ExpiredAttestation_ReturnsFalse() public {
        uint64 issuedAt = uint64(block.timestamp);
        uint64 expiresAt = issuedAt + 3600;
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", issuedAt, expiresAt, 0);
        bytes32 id = registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));
        assertTrue(registry.isValid(id));

        vm.warp(issuedAt + 3601);
        assertFalse(registry.isValid(id));
        (, bool revoked, bool expired) = registry.getAttestation(id);
        assertFalse(revoked);
        assertTrue(expired);
    }

    function test_SubmitAttestation_InvalidExpiry_Reverts() public {
        uint64 issuedAt = uint64(block.timestamp);
        uint64 expiresAt = issuedAt - 1;
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", issuedAt, expiresAt, 0);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_InvalidExpiry.selector);
        registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));
    }

    function test_SubmitAttestation_ZeroExpiry_NoExpiry() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(subject, NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);
        bytes32 id = registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));

        vm.warp(block.timestamp + 365 days);
        assertTrue(registry.isValid(id));
    }

    // -------------------------------------------------------------------------
    // Invalid subject
    // -------------------------------------------------------------------------

    function test_SubmitAttestation_ZeroSubject_Reverts() public {
        IAttestationRegistry.Attestation memory a =
            _makeAttestation(address(0), NOI_TYPE, keccak256("x"), bytes32(0), "", 0, 0, 0);

        vm.expectRevert(IAttestationRegistry.AttestationRegistry_InvalidSubject.selector);
        registry.submitAttestation(a, _signAttestation(a, ISSUER_KEY));
    }

    function test_Constructor_ZeroAdmin_Reverts() public {
        vm.expectRevert(IAttestationRegistry.AttestationRegistry_InvalidSubject.selector);
        new AttestationRegistry(address(0));
    }
}
