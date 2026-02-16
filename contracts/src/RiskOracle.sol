// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRiskOracle} from "./interfaces/IRiskOracle.sol";
import {SignatureVerifier} from "./libraries/SignatureVerifier.sol";

/// @title RiskOracle
/// @notice Semi-trusted EIP-712 signed oracle for risk payload verification
/// @dev Designed for Base Sepolia; upgrade path to decentralized oracle
contract RiskOracle is IRiskOracle {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice EIP-712 domain name
    string public constant DOMAIN_NAME = "OCX Risk Oracle";

    /// @notice EIP-712 domain version
    string public constant DOMAIN_VERSION = "1";

    /// @notice Maximum age of a payload signature in seconds (e.g., 5 minutes)
    uint256 public constant PAYLOAD_VALIDITY_WINDOW = 300;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Authorized oracle signer (backend key)
    address public immutable oracleSigner;

    /// @notice Next nonce per user (sequential, prevents replay)
    mapping(address => uint256) public nextNonce;

    /// @notice Tracks consumed nonces: keccak256(user, nonce) => true if used (legacy)
    mapping(bytes32 => bool) public usedNonces;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event RiskPayloadVerified(address indexed user, uint256 nonce, uint256 score);
    event RiskPayloadV2Verified(
        address indexed user,
        uint64 nonce,
        uint16 score,
        uint8 riskTier,
        uint16 confidenceBps,
        bytes32 modelId,
        bytes32 reasonsHash,
        bytes32 evidenceHash
    );
    event NonceConsumed(address indexed user, uint256 nonce);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error RiskOracle_InvalidSignature();
    error RiskOracle_ExpiredTimestamp();
    error RiskOracle_ReplayAttack();
    error RiskOracle_InvalidPayload();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _oracleSigner Address that signs risk payloads (backend wallet)
    constructor(address _oracleSigner) {
        if (_oracleSigner == address(0)) revert RiskOracle_InvalidPayload();
        oracleSigner = _oracleSigner;
    }

    // -------------------------------------------------------------------------
    // External
    // -------------------------------------------------------------------------

    /// @inheritdoc IRiskOracle
    function verifyRiskPayload(RiskPayload calldata payload, bytes calldata signature)
        external
        override
        returns (bool)
    {
        _validateAndConsume(payload, signature);
        emit RiskPayloadVerified(payload.user, payload.nonce, payload.score);
        return true;
    }

    /// @inheritdoc IRiskOracle
    function verifyRiskPayloadView(RiskPayload calldata payload, bytes calldata signature)
        external
        view
        override
        returns (bool)
    {
        return _verify(payload, signature);
    }

    /// @inheritdoc IRiskOracle
    function verifyRiskPayloadV2(RiskPayloadV2 calldata payload, bytes calldata signature)
        external
        override
        returns (bool)
    {
        _validateAndConsumeV2(payload, signature);
        emit RiskPayloadV2Verified(
            payload.user,
            payload.nonce,
            payload.score,
            payload.riskTier,
            payload.confidenceBps,
            payload.modelId,
            payload.reasonsHash,
            payload.evidenceHash
        );
        return true;
    }

    /// @inheritdoc IRiskOracle
    function verifyRiskPayloadV2View(RiskPayloadV2 calldata payload, bytes calldata signature)
        external
        view
        override
        returns (bool)
    {
        return _verifyV2(payload, signature);
    }

    /// @notice Returns the EIP-712 domain separator
    function domainSeparator() external view returns (bytes32) {
        return
            SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this));
    }

    /// @notice Returns the EIP-712 digest for a payload (for off-chain signers + testing)
    function getPayloadDigest(RiskPayload calldata payload) external view returns (bytes32) {
        bytes32 structHash = SignatureVerifier.hashRiskPayload(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.timestamp,
            payload.nonce
        );
        return
            SignatureVerifier.toTypedDataHash(
                SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
                structHash
            );
    }

    /// @notice Returns the EIP-712 digest for a v2 payload
    function getPayloadDigestV2(RiskPayloadV2 calldata payload) external view returns (bytes32) {
        bytes32 structHash = SignatureVerifier.hashRiskPayloadV2(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.confidenceBps,
            payload.modelId,
            payload.reasonsHash,
            payload.evidenceHash,
            payload.timestamp,
            payload.nonce
        );
        return
            SignatureVerifier.toTypedDataHash(
                SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
                structHash
            );
    }

    /// @notice Checks if a nonce has been consumed for a user
    function isNonceUsed(address user, uint256 nonce) external view returns (bool) {
        return usedNonces[_nonceKey(user, nonce)];
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _verify(RiskPayload calldata payload, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (block.timestamp > payload.timestamp + PAYLOAD_VALIDITY_WINDOW) {
            return false; // Expired
        }
        if (payload.nonce != nextNonce[payload.user]) {
            return false; // Wrong/replayed nonce
        }

        bytes32 structHash = SignatureVerifier.hashRiskPayload(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.timestamp,
            payload.nonce
        );

        bytes32 digest = SignatureVerifier.toTypedDataHash(
            SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );

        address signer = SignatureVerifier.recover(digest, signature);
        return signer == oracleSigner;
    }

    function _validateAndConsume(RiskPayload calldata payload, bytes calldata signature)
        internal
    {
        if (block.timestamp > payload.timestamp + PAYLOAD_VALIDITY_WINDOW) {
            revert RiskOracle_ExpiredTimestamp();
        }

        if (payload.nonce != nextNonce[payload.user]) revert RiskOracle_ReplayAttack();
        nextNonce[payload.user]++;

        bytes32 structHash = SignatureVerifier.hashRiskPayload(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.timestamp,
            payload.nonce
        );

        bytes32 digest = SignatureVerifier.toTypedDataHash(
            SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );

        address signer = SignatureVerifier.recover(digest, signature);
        if (signer != oracleSigner) revert RiskOracle_InvalidSignature();

        usedNonces[_nonceKey(payload.user, payload.nonce)] = true;
        emit NonceConsumed(payload.user, payload.nonce);
    }

    function _verifyV2(RiskPayloadV2 calldata payload, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (block.timestamp > payload.timestamp + PAYLOAD_VALIDITY_WINDOW) return false;
        if (payload.nonce != nextNonce[payload.user]) return false;

        bytes32 structHash = SignatureVerifier.hashRiskPayloadV2(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.confidenceBps,
            payload.modelId,
            payload.reasonsHash,
            payload.evidenceHash,
            payload.timestamp,
            payload.nonce
        );
        bytes32 digest = SignatureVerifier.toTypedDataHash(
            SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );
        return SignatureVerifier.recover(digest, signature) == oracleSigner;
    }

    function _validateAndConsumeV2(RiskPayloadV2 calldata payload, bytes calldata signature)
        internal
    {
        if (block.timestamp > payload.timestamp + PAYLOAD_VALIDITY_WINDOW) {
            revert RiskOracle_ExpiredTimestamp();
        }
        if (payload.nonce != nextNonce[payload.user]) revert RiskOracle_ReplayAttack();
        nextNonce[payload.user]++;

        bytes32 structHash = SignatureVerifier.hashRiskPayloadV2(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.confidenceBps,
            payload.modelId,
            payload.reasonsHash,
            payload.evidenceHash,
            payload.timestamp,
            payload.nonce
        );
        bytes32 digest = SignatureVerifier.toTypedDataHash(
            SignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );
        if (SignatureVerifier.recover(digest, signature) != oracleSigner) {
            revert RiskOracle_InvalidSignature();
        }

        usedNonces[_nonceKey(payload.user, payload.nonce)] = true;
        emit NonceConsumed(payload.user, payload.nonce);
    }

    function _nonceKey(address user, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, nonce));
    }
}
