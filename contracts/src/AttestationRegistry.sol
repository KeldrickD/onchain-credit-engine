// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAttestationRegistry} from "./interfaces/IAttestationRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AttestationSignatureVerifier} from "./libraries/AttestationSignatureVerifier.sol";

/// @title AttestationRegistry
/// @notice Verifiable underwriting claims: NOI, DSCR, KYB, sponsor track record, etc.
/// @dev EIP-712 signed; role-gated issuers; revocation + expiry; queryable by subject + type
contract AttestationRegistry is IAttestationRegistry, AccessControl {
    string public constant DOMAIN_NAME = "OCX Attestation Registry";
    string public constant DOMAIN_VERSION = "2";

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    struct StoredAttestationInternal {
        address subject;
        bytes32 attestationType;
        bytes32 dataHash;
        bytes32 data;
        string uri;
        uint64 issuedAt;
        uint64 expiresAt;
        address issuer;
    }

    mapping(bytes32 => StoredAttestationInternal) private _attestations;
    mapping(address => mapping(bytes32 => bytes32)) private _latestBySubjectAndType;
    mapping(address => uint64) public nextNonce;
    mapping(bytes32 => bool) private _revoked;

    constructor(address admin) AccessControl() {
        if (admin == address(0)) revert AttestationRegistry_InvalidSubject();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function submitAttestation(Attestation calldata a, bytes calldata signature)
        external
        override
        returns (bytes32 attestationId)
    {
        if (a.subject == address(0)) revert AttestationRegistry_InvalidSubject();
        if (a.nonce != nextNonce[a.subject]) revert AttestationRegistry_InvalidNonce();
        if (a.expiresAt != 0 && a.expiresAt <= a.issuedAt) revert AttestationRegistry_InvalidExpiry();

        bytes32 structHash = AttestationSignatureVerifier.hashAttestation(
            a.subject,
            a.attestationType,
            a.dataHash,
            a.data,
            a.uri,
            a.issuedAt,
            a.expiresAt,
            a.nonce
        );
        bytes32 digest = AttestationSignatureVerifier.toTypedDataHash(
            AttestationSignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );
        address issuer = AttestationSignatureVerifier.recover(digest, signature);
        if (!hasRole(ISSUER_ROLE, issuer)) revert AttestationRegistry_IssuerNotAllowed();

        attestationId = keccak256(
            abi.encode(a.subject, a.attestationType, a.dataHash, a.data, a.issuedAt, issuer, a.nonce)
        );

        _attestations[attestationId] = StoredAttestationInternal({
            subject: a.subject,
            attestationType: a.attestationType,
            dataHash: a.dataHash,
            data: a.data,
            uri: a.uri,
            issuedAt: a.issuedAt,
            expiresAt: a.expiresAt,
            issuer: issuer
        });
        _latestBySubjectAndType[a.subject][a.attestationType] = attestationId;
        nextNonce[a.subject] = a.nonce + 1;

        emit Attested(
            attestationId,
            a.subject,
            a.attestationType,
            issuer,
            a.issuedAt,
            a.expiresAt,
            a.dataHash,
            a.uri
        );
    }

    function revoke(bytes32 attestationId) external override {
        StoredAttestationInternal storage att = _attestations[attestationId];
        if (att.issuer == address(0)) revert AttestationRegistry_NotRevocable();
        if (_revoked[attestationId]) revert AttestationRegistry_AlreadyRevoked();

        bool canRevoke = hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || att.issuer == msg.sender;
        if (!canRevoke) revert AttestationRegistry_NotRevocable();

        _revoked[attestationId] = true;
        emit Revoked(attestationId, msg.sender, block.timestamp);
    }

    function getLatest(address subject, bytes32 attestationType)
        external
        view
        override
        returns (StoredAttestation memory att, bool revoked, bool expired)
    {
        bytes32 id = _latestBySubjectAndType[subject][attestationType];
        if (id == bytes32(0)) {
            return (StoredAttestation(subject, attestationType, bytes32(0), bytes32(0), "", 0, 0, address(0)), true, false);
        }
        return getAttestation(id);
    }

    function getLatestAttestationId(address subject, bytes32 attestationType) external view override returns (bytes32) {
        return _latestBySubjectAndType[subject][attestationType];
    }

    function getAttestation(bytes32 attestationId)
        external
        view
        override
        returns (StoredAttestation memory att, bool revoked, bool expired)
    {
        StoredAttestationInternal storage s = _attestations[attestationId];
        revoked = _revoked[attestationId];
        expired = s.expiresAt != 0 && block.timestamp >= s.expiresAt;
        att = StoredAttestation({
            subject: s.subject,
            attestationType: s.attestationType,
            dataHash: s.dataHash,
            data: s.data,
            uri: s.uri,
            issuedAt: s.issuedAt,
            expiresAt: s.expiresAt,
            issuer: s.issuer
        });
    }

    /// @notice EIP-712 digest for attestation (for signing offchain)
    function getAttestationDigest(Attestation calldata a) external view returns (bytes32) {
        bytes32 structHash = AttestationSignatureVerifier.hashAttestation(
            a.subject,
            a.attestationType,
            a.dataHash,
            a.data,
            a.uri,
            a.issuedAt,
            a.expiresAt,
            a.nonce
        );
        return AttestationSignatureVerifier.toTypedDataHash(
            AttestationSignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );
    }

    function isValid(bytes32 attestationId) external view override returns (bool) {
        if (_attestations[attestationId].issuer == address(0)) return false;
        if (_revoked[attestationId]) return false;
        StoredAttestationInternal storage s = _attestations[attestationId];
        if (s.expiresAt != 0 && block.timestamp >= s.expiresAt) return false;
        return true;
    }
}
