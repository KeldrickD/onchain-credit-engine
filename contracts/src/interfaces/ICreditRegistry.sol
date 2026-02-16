// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRiskOracle} from "./IRiskOracle.sol";

interface ICreditRegistry {
    struct CreditProfile {
        uint256 score;          // 0 - 1000
        uint256 riskTier;       // 0 - 5
        uint256 lastUpdated;
        bytes32 modelId;
        uint16 confidenceBps;
        bytes32 reasonsHash;
        bytes32 evidenceHash;
    }

    /// @notice Updates a user's credit profile. Only succeeds when oracle payload is valid.
    /// @dev Calls riskOracle.verifyRiskPayload (consumes nonce). Atomic: verify + store.
    /// @param payload Signed risk payload from oracle
    /// @param signature EIP-712 signature
    function updateCreditProfile(
        IRiskOracle.RiskPayload calldata payload,
        bytes calldata signature
    ) external;

    /// @notice Updates a user's profile using v2 payload with model metadata.
    function updateCreditProfileV2(
        IRiskOracle.RiskPayloadV2 calldata payload,
        bytes calldata signature
    ) external;

    /// @notice Returns the credit profile for a user
    /// @param user Address to query
    function getCreditProfile(address user) external view returns (CreditProfile memory);
}
