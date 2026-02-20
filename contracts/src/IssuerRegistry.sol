// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIssuerRegistry} from "./interfaces/IIssuerRegistry.sol";

contract IssuerRegistry is AccessControl, IIssuerRegistry {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    error IssuerRegistry_InvalidAddress();
    error IssuerRegistry_InvalidBps();

    event IssuerSet(
        address indexed issuer,
        bool active,
        uint16 trustScoreBps,
        bytes32 metadataHash,
        string metadataURI
    );
    event IssuerActiveSet(address indexed issuer, bool active);
    event IssuerTrustScoreSet(address indexed issuer, uint16 trustScoreBps);
    event IssuerMetadataSet(address indexed issuer, bytes32 metadataHash, string metadataURI);
    event IssuerTypePermissionSet(address indexed issuer, bytes32 indexed attestationType, bool allowed);
    event MinTrustScoreForTypeSet(bytes32 indexed attestationType, uint16 minTrustBps);

    mapping(address => IssuerInfo) private _issuers;
    mapping(address => mapping(bytes32 => bool)) private _allowedForType;
    mapping(bytes32 => uint16) private _minTrustBpsForType;

    constructor(address admin) {
        if (admin == address(0)) revert IssuerRegistry_InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    modifier onlyManager() {
        if (!hasRole(MANAGER_ROLE, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, MANAGER_ROLE);
        _;
    }

    function getIssuer(address issuer) external view returns (IssuerInfo memory) {
        return _issuers[issuer];
    }

    function isActive(address issuer) public view returns (bool) {
        return _issuers[issuer].active;
    }

    function trustScoreBps(address issuer) public view returns (uint16) {
        return _issuers[issuer].trustScoreBps;
    }

    function isAllowedForType(address issuer, bytes32 attestationType) public view returns (bool) {
        return _allowedForType[issuer][attestationType];
    }

    function minTrustScoreBpsForType(bytes32 attestationType) public view returns (uint16) {
        return _minTrustBpsForType[attestationType];
    }

    function isTrustedForType(address issuer, bytes32 attestationType) external view returns (bool) {
        IssuerInfo memory info = _issuers[issuer];
        if (!info.active) return false;
        if (!_allowedForType[issuer][attestationType]) return false;
        return info.trustScoreBps >= _minTrustBpsForType[attestationType];
    }

    function setIssuer(
        address issuer,
        bool active,
        uint16 trustScoreBps_,
        bytes32 metadataHash,
        string calldata metadataURI
    ) external onlyManager {
        if (issuer == address(0)) revert IssuerRegistry_InvalidAddress();
        if (trustScoreBps_ > 10_000) revert IssuerRegistry_InvalidBps();

        IssuerInfo storage s = _issuers[issuer];
        s.trustScoreBps = trustScoreBps_;
        s.metadataHash = metadataHash;
        s.metadataURI = metadataURI;
        if (active && !s.active) {
            s.since = uint64(block.timestamp);
        }
        s.active = active;

        emit IssuerSet(issuer, active, trustScoreBps_, metadataHash, metadataURI);
    }

    function setIssuerActive(address issuer, bool active) external onlyManager {
        if (issuer == address(0)) revert IssuerRegistry_InvalidAddress();
        IssuerInfo storage s = _issuers[issuer];
        if (active && !s.active) {
            s.since = uint64(block.timestamp);
        }
        s.active = active;
        emit IssuerActiveSet(issuer, active);
    }

    function setIssuerTrustScore(address issuer, uint16 trustScoreBps_) external onlyManager {
        if (issuer == address(0)) revert IssuerRegistry_InvalidAddress();
        if (trustScoreBps_ > 10_000) revert IssuerRegistry_InvalidBps();
        _issuers[issuer].trustScoreBps = trustScoreBps_;
        emit IssuerTrustScoreSet(issuer, trustScoreBps_);
    }

    function setIssuerMetadata(address issuer, bytes32 metadataHash, string calldata metadataURI) external onlyManager {
        if (issuer == address(0)) revert IssuerRegistry_InvalidAddress();
        IssuerInfo storage s = _issuers[issuer];
        s.metadataHash = metadataHash;
        s.metadataURI = metadataURI;
        emit IssuerMetadataSet(issuer, metadataHash, metadataURI);
    }

    function setIssuerTypePermission(address issuer, bytes32 attestationType, bool allowed) external onlyManager {
        if (issuer == address(0)) revert IssuerRegistry_InvalidAddress();
        _allowedForType[issuer][attestationType] = allowed;
        emit IssuerTypePermissionSet(issuer, attestationType, allowed);
    }

    function setIssuerTypePermissions(address issuer, bytes32[] calldata types, bool allowed) external onlyManager {
        if (issuer == address(0)) revert IssuerRegistry_InvalidAddress();
        for (uint256 i = 0; i < types.length; i++) {
            _allowedForType[issuer][types[i]] = allowed;
            emit IssuerTypePermissionSet(issuer, types[i], allowed);
        }
    }

    function setMinTrustScoreBpsForType(bytes32 attestationType, uint16 minTrustBps) external onlyManager {
        if (minTrustBps > 10_000) revert IssuerRegistry_InvalidBps();
        _minTrustBpsForType[attestationType] = minTrustBps;
        emit MinTrustScoreForTypeSet(attestationType, minTrustBps);
    }
}
