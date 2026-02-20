// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIssuerRegistry {
    struct IssuerInfo {
        bool active;
        uint16 trustScoreBps; // 0..10000
        uint64 since; // activation timestamp
        bytes32 metadataHash; // optional metadata hash
        string metadataURI; // optional metadata URI
    }

    function getIssuer(address issuer) external view returns (IssuerInfo memory);
    function isActive(address issuer) external view returns (bool);
    function trustScoreBps(address issuer) external view returns (uint16);

    function isAllowedForType(address issuer, bytes32 attestationType) external view returns (bool);
    function minTrustScoreBpsForType(bytes32 attestationType) external view returns (uint16);
    function isTrustedForType(address issuer, bytes32 attestationType) external view returns (bool);

    function setIssuer(
        address issuer,
        bool active,
        uint16 trustScoreBps_,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external;

    function setIssuerActive(address issuer, bool active) external;
    function setIssuerTrustScore(address issuer, uint16 trustScoreBps_) external;
    function setIssuerMetadata(address issuer, bytes32 metadataHash, string calldata metadataURI) external;

    function setIssuerTypePermission(address issuer, bytes32 attestationType, bool allowed) external;
    function setIssuerTypePermissions(address issuer, bytes32[] calldata types, bool allowed) external;

    function setMinTrustScoreBpsForType(bytes32 attestationType, uint16 minTrustBps) external;
}
