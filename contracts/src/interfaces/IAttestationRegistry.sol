// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAttestationRegistry
/// @notice Verifiable underwriting claims: NOI, DSCR, KYB, etc.
interface IAttestationRegistry {
    struct Attestation {
        address subject;
        bytes32 attestationType;
        bytes32 dataHash;
        bytes32 data;       // numeric value (e.g. DSCR_BPS as uint in bytes32); 0x0 for presence-only
        string uri;
        uint64 issuedAt;
        uint64 expiresAt;
        uint64 nonce;
    }

    struct StoredAttestation {
        address subject;
        bytes32 attestationType;
        bytes32 dataHash;
        bytes32 data;
        string uri;
        uint64 issuedAt;
        uint64 expiresAt;
        address issuer;
    }

    event Attested(
        bytes32 indexed attestationId,
        address indexed subject,
        bytes32 indexed attestationType,
        address issuer,
        uint64 issuedAt,
        uint64 expiresAt,
        bytes32 dataHash,
        string uri
    );
    event Revoked(bytes32 indexed attestationId, address indexed revokedBy, uint256 timestamp);

    error AttestationRegistry_InvalidSignature();
    error AttestationRegistry_IssuerNotAllowed();
    error AttestationRegistry_InvalidNonce();
    error AttestationRegistry_InvalidExpiry();
    error AttestationRegistry_InvalidSubject();
    error AttestationRegistry_AlreadyRevoked();
    error AttestationRegistry_NotRevocable();

    function submitAttestation(Attestation calldata a, bytes calldata signature) external returns (bytes32 attestationId);
    function revoke(bytes32 attestationId) external;

    function getLatest(address subject, bytes32 attestationType)
        external
        view
        returns (StoredAttestation memory att, bool revoked, bool expired);

    function getLatestAttestationId(address subject, bytes32 attestationType) external view returns (bytes32);

    function getAttestation(bytes32 attestationId)
        external
        view
        returns (StoredAttestation memory att, bool revoked, bool expired);

    function isValid(bytes32 attestationId) external view returns (bool);
    function nextNonce(address subject) external view returns (uint64);
}
