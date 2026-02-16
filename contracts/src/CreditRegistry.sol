// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICreditRegistry} from "./interfaces/ICreditRegistry.sol";
import {IRiskOracle} from "./interfaces/IRiskOracle.sol";

/// @title CreditRegistry
/// @notice Stores user CreditProfiles; updates gated by valid oracle-signed RiskPayload
/// @dev Calls RiskOracle.verifyRiskPayload (consumes nonce) — atomic verify + store
contract CreditRegistry is ICreditRegistry {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant MAX_SCORE = 1000;
    uint256 public constant MAX_RISK_TIER = 5;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IRiskOracle public immutable riskOracle;

    mapping(address => CreditProfile) private profiles;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event CreditProfileUpdated(
        address indexed user,
        uint256 score,
        uint256 riskTier,
        uint256 timestamp,
        uint256 nonce
    );
    event CreditProfileUpdatedV2(
        address indexed user,
        uint16 score,
        uint8 riskTier,
        uint16 confidenceBps,
        bytes32 modelId,
        bytes32 reasonsHash,
        bytes32 evidenceHash,
        uint64 timestamp,
        uint64 nonce
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error CreditRegistry_ScoreOutOfRange();
    error CreditRegistry_InvalidTier();
    error CreditRegistry_InvalidConfidence();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _riskOracle RiskOracle contract that verifies and consumes payloads
    constructor(address _riskOracle) {
        riskOracle = IRiskOracle(_riskOracle);
    }

    // -------------------------------------------------------------------------
    // External
    // -------------------------------------------------------------------------

    /// @inheritdoc ICreditRegistry
    function updateCreditProfile(
        IRiskOracle.RiskPayload calldata payload,
        bytes calldata signature
    ) external override {
        if (payload.score > MAX_SCORE) revert CreditRegistry_ScoreOutOfRange();
        if (payload.riskTier > MAX_RISK_TIER) revert CreditRegistry_InvalidTier();

        // Oracle verifies signature, timestamp, nonce; consumes nonce
        riskOracle.verifyRiskPayload(payload, signature);

        profiles[payload.user] = CreditProfile({
            score: payload.score,
            riskTier: payload.riskTier,
            lastUpdated: block.timestamp,
            modelId: bytes32(0),
            confidenceBps: 0,
            reasonsHash: bytes32(0),
            evidenceHash: bytes32(0)
        });

        emit CreditProfileUpdated(
            payload.user,
            payload.score,
            payload.riskTier,
            payload.timestamp,
            payload.nonce
        );
    }

    /// @inheritdoc ICreditRegistry
    function updateCreditProfileV2(
        IRiskOracle.RiskPayloadV2 calldata payload,
        bytes calldata signature
    ) external override {
        if (payload.score > MAX_SCORE) revert CreditRegistry_ScoreOutOfRange();
        if (payload.riskTier > 3) revert CreditRegistry_InvalidTier();
        if (payload.confidenceBps > 10_000) revert CreditRegistry_InvalidConfidence();

        riskOracle.verifyRiskPayloadV2(payload, signature);

        profiles[payload.user] = CreditProfile({
            score: payload.score,
            riskTier: payload.riskTier,
            lastUpdated: block.timestamp,
            modelId: payload.modelId,
            confidenceBps: payload.confidenceBps,
            reasonsHash: payload.reasonsHash,
            evidenceHash: payload.evidenceHash
        });

        emit CreditProfileUpdatedV2(
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
    }

    /// @inheritdoc ICreditRegistry
    function getCreditProfile(address user) external view override returns (CreditProfile memory) {
        return profiles[user];
    }
}
