// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRiskOracle {
    struct RiskPayload {
        address user;
        uint256 score;
        uint256 riskTier;
        uint256 timestamp;
        uint256 nonce;
    }

    struct RiskPayloadV2 {
        address user;
        uint16 score;         // 0-1000
        uint8 riskTier;       // 0-3
        uint16 confidenceBps; // 0-10000
        bytes32 modelId;
        bytes32 reasonsHash;
        bytes32 evidenceHash;
        uint64 timestamp;
        uint64 nonce;
    }

    struct RiskPayloadV2ByKey {
        bytes32 subjectKey;
        uint16 score;
        uint8 riskTier;
        uint16 confidenceBps;
        bytes32 modelId;
        bytes32 reasonsHash;
        bytes32 evidenceHash;
        uint64 timestamp;
        uint64 nonce;
    }

    /// @notice Verifies a risk payload signature, validates timestamp/nonce, and consumes nonce if valid
    /// @dev Consumes nonce to prevent replay attacks. Call only when payload will be used.
    /// @param payload The risk payload containing user, score, riskTier, timestamp, nonce
    /// @param signature EIP-712 signature from the oracle signer
    /// @return True if signature is valid and payload passes all checks (nonce consumed)
    function verifyRiskPayload(RiskPayload calldata payload, bytes calldata signature)
        external
        returns (bool);

    /// @notice View-only verification (does not consume nonce). Use for pre-checks.
    function verifyRiskPayloadView(RiskPayload calldata payload, bytes calldata signature)
        external
        view
        returns (bool);

    /// @notice Verifies and consumes a v2 risk payload.
    function verifyRiskPayloadV2(RiskPayloadV2 calldata payload, bytes calldata signature)
        external
        returns (bool);

    /// @notice View-only verification for v2 payload (no nonce consume).
    function verifyRiskPayloadV2View(RiskPayloadV2 calldata payload, bytes calldata signature)
        external
        view
        returns (bool);

    /// @notice Next nonce for a subject key (bytes32); used for deal/entity commits.
    function nextNonceKey(bytes32 subjectKey) external view returns (uint64);

    /// @notice Verifies and consumes a v2-by-key payload (subject/deal profile).
    function verifyRiskPayloadV2ByKey(RiskPayloadV2ByKey calldata payload, bytes calldata signature)
        external
        returns (bool);

    /// @notice EIP-712 digest for v2-by-key payload.
    function getPayloadDigestV2ByKey(RiskPayloadV2ByKey calldata payload) external view returns (bytes32);
}
