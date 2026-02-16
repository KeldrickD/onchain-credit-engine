// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRiskEngineV2
/// @notice Deterministic, evidence-backed credit evaluation for CapitalMethod
interface IRiskEngineV2 {
    struct RiskOutput {
        uint16 score;          // 0–1000
        uint8 tier;            // 0–3 (matches lending tiers)
        uint16 confidenceBps;  // 0–10000
        bytes32 modelId;       // e.g. keccak256("RISK_V2_2026_02_15")
        bytes32[] reasonCodes;
        bytes32[] evidence;    // attestationIds used
    }

    function evaluate(address subject) external view returns (RiskOutput memory);
}
