// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRiskOracle} from "./IRiskOracle.sol";

interface ICreditRegistry {
    struct CreditProfile {
        uint256 score;          // 0 - 1000
        uint256 riskTier;       // 0 - 5
        uint256 lastUpdated;
        uint32 modelId;         // Optional: model version for future signaling
        uint16 confidenceBps;  // Optional: confidence in basis points
    }

    /// @notice Updates a user's credit profile. Only succeeds when oracle payload is valid.
    /// @dev Calls riskOracle.verifyRiskPayload (consumes nonce). Atomic: verify + store.
    /// @param payload Signed risk payload from oracle
    /// @param signature EIP-712 signature
    function updateCreditProfile(
        IRiskOracle.RiskPayload calldata payload,
        bytes calldata signature
    ) external;

    /// @notice Returns the credit profile for a user
    /// @param user Address to query
    function getCreditProfile(address user) external view returns (CreditProfile memory);
}
