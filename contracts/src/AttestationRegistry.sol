// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAttestationRegistry} from "./interfaces/IAttestationRegistry.sol";
import {IIssuerRegistry} from "./interfaces/IIssuerRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AttestationSignatureVerifier} from "./libraries/AttestationSignatureVerifier.sol";

/// @title AttestationRegistry
/// @notice Verifiable underwriting claims: NOI, DSCR, KYB, sponsor track record, etc.
/// @dev EIP-712 signed; role-gated issuers; revocation + expiry; queryable by subject + type
contract AttestationRegistry is IAttestationRegistry, AccessControl {
    string public constant DOMAIN_NAME = "OCX Attestation Registry";
    string public constant DOMAIN_VERSION = "2";

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    enum AttestationKind { NONE, WALLET, SUBJECT }
    mapping(bytes32 => AttestationKind) public kindOf;

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

    struct StoredSubjectAttestationInternal {
        bytes32 subjectId;
        bytes32 attestationType;
        bytes32 dataHash;
        bytes32 data;
        string uri;
        uint64 issuedAt;
        uint64 expiresAt;
        address issuer;
    }

    bytes32 private constant SUBJECT_ATTESTATION_ID_PREFIX = keccak256("SUBJECT_ATTESTATION_V1");
    event IssuerRegistrySet(address indexed oldRegistry, address indexed newRegistry);

    mapping(bytes32 => StoredAttestationInternal) private _attestations;
    mapping(bytes32 => StoredSubjectAttestationInternal) private _subjectAttestations;
    mapping(address => mapping(bytes32 => bytes32)) private _latestBySubjectAndType;
    mapping(bytes32 => mapping(bytes32 => bytes32)) private _latestBySubjectIdAndType;
    mapping(address => uint64) public nextNonce;
    mapping(bytes32 => uint64) public nextSubjectNonce;
    mapping(bytes32 => bool) private _revoked;
    mapping(bytes32 => address) private _issuerByAttestationId;
    address public issuerRegistry;

    constructor(address admin) AccessControl() {
        if (admin == address(0)) revert AttestationRegistry_InvalidSubject();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setIssuerRegistry(address issuerRegistry_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        emit IssuerRegistrySet(issuerRegistry, issuerRegistry_);
        issuerRegistry = issuerRegistry_;
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
        _issuerByAttestationId[attestationId] = issuer;
        kindOf[attestationId] = AttestationKind.WALLET;

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

    function submitSubjectAttestation(SubjectAttestation calldata a, bytes calldata signature)
        external
        override
        returns (bytes32 attestationId)
    {
        if (a.subjectId == bytes32(0)) revert AttestationRegistry_InvalidSubjectId();
        if (a.nonce != nextSubjectNonce[a.subjectId]) revert AttestationRegistry_InvalidNonce();
        if (a.expiresAt != 0 && a.expiresAt <= a.issuedAt) revert AttestationRegistry_InvalidExpiry();

        bytes32 structHash = AttestationSignatureVerifier.hashSubjectAttestation(
            a.subjectId,
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
            abi.encode(
                SUBJECT_ATTESTATION_ID_PREFIX,
                a.subjectId,
                a.attestationType,
                a.dataHash,
                a.data,
                a.issuedAt,
                issuer,
                a.nonce
            )
        );

        _subjectAttestations[attestationId] = StoredSubjectAttestationInternal({
            subjectId: a.subjectId,
            attestationType: a.attestationType,
            dataHash: a.dataHash,
            data: a.data,
            uri: a.uri,
            issuedAt: a.issuedAt,
            expiresAt: a.expiresAt,
            issuer: issuer
        });
        _latestBySubjectIdAndType[a.subjectId][a.attestationType] = attestationId;
        nextSubjectNonce[a.subjectId] = a.nonce + 1;
        _issuerByAttestationId[attestationId] = issuer;
        kindOf[attestationId] = AttestationKind.SUBJECT;

        emit SubjectAttested(
            attestationId,
            a.subjectId,
            a.attestationType,
            issuer,
            a.issuedAt,
            a.expiresAt,
            a.dataHash,
            a.uri
        );
    }

    function revoke(bytes32 attestationId) external override {
        address issuer = _issuerByAttestationId[attestationId];
        if (issuer == address(0)) revert AttestationRegistry_NotRevocable();
        if (_revoked[attestationId]) revert AttestationRegistry_AlreadyRevoked();

        bool canRevoke = hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || issuer == msg.sender;
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

    function getLatestSubject(bytes32 subjectId, bytes32 attestationType)
        external
        view
        override
        returns (StoredSubjectAttestation memory att, bool revoked, bool expired)
    {
        bytes32 id = _latestBySubjectIdAndType[subjectId][attestationType];
        if (id == bytes32(0)) {
            return (
                StoredSubjectAttestation(subjectId, attestationType, bytes32(0), bytes32(0), "", 0, 0, address(0)),
                true,
                false
            );
        }
        return getSubjectAttestation(id);
    }

    function getLatestSubjectAttestationId(bytes32 subjectId, bytes32 attestationType)
        external
        view
        override
        returns (bytes32)
    {
        return _latestBySubjectIdAndType[subjectId][attestationType];
    }

    function getAttestation(bytes32 attestationId)
        public
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

    function getSubjectAttestation(bytes32 attestationId)
        public
        view
        override
        returns (StoredSubjectAttestation memory att, bool revoked, bool expired)
    {
        StoredSubjectAttestationInternal storage s = _subjectAttestations[attestationId];
        revoked = _revoked[attestationId];
        expired = s.expiresAt != 0 && block.timestamp >= s.expiresAt;
        att = StoredSubjectAttestation({
            subjectId: s.subjectId,
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

    /// @notice EIP-712 digest for subject attestation (for signing offchain)
    function getSubjectAttestationDigest(SubjectAttestation calldata a) external view returns (bytes32) {
        bytes32 structHash = AttestationSignatureVerifier.hashSubjectAttestation(
            a.subjectId,
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
        if (kindOf[attestationId] == AttestationKind.NONE) return false;
        if (_revoked[attestationId]) return false;
        if (kindOf[attestationId] == AttestationKind.WALLET) {
            StoredAttestationInternal storage a = _attestations[attestationId];
            if (a.issuer == address(0)) return false;
            if (a.expiresAt != 0 && block.timestamp >= a.expiresAt) return false;
            return true;
        }
        // SUBJECT
        StoredSubjectAttestationInternal storage s = _subjectAttestations[attestationId];
        if (s.issuer == address(0)) return false;
        if (s.expiresAt != 0 && block.timestamp >= s.expiresAt) return false;
        return true;
    }

    function isTrustedIssuerForAttestation(bytes32 attestationId) external view override returns (bool) {
        if (issuerRegistry == address(0)) return false;

        AttestationKind k = kindOf[attestationId];
        if (k == AttestationKind.NONE) return false;

        bytes32 attType;
        address issuer;
        if (k == AttestationKind.WALLET) {
            StoredAttestationInternal storage a = _attestations[attestationId];
            attType = a.attestationType;
            issuer = a.issuer;
        } else {
            StoredSubjectAttestationInternal storage s = _subjectAttestations[attestationId];
            attType = s.attestationType;
            issuer = s.issuer;
        }
        if (issuer == address(0)) return false;
        return IIssuerRegistry(issuerRegistry).isTrustedForType(issuer, attType);
    }
}
