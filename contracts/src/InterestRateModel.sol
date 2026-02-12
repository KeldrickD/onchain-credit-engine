// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title InterestRateModel
/// @notice Tier-based interest rates (bps). Pure functions for auditability.
library InterestRateModel {
    // -------------------------------------------------------------------------
    // Tier mapping (matches LoanEngine score bands)
    // -------------------------------------------------------------------------
    // Tier 0: score 0–399   → 50% LTV, 1500 bps (15% APY)
    // Tier 1: score 400–699  → 65% LTV, 1000 bps (10% APY)
    // Tier 2: score 700–850  → 75% LTV, 700 bps  (7% APY)
    // Tier 3: score 851–1000 → 85% LTV, 500 bps  (5% APY)

    /// @return rateBps Annual interest rate in basis points for the given tier
    function rateBpsForTier(uint256 tier) internal pure returns (uint256 rateBps) {
        if (tier == 0) return 1500;
        if (tier == 1) return 1000;
        if (tier == 2) return 700;
        if (tier == 3) return 500;
        return 1500; // fallback for invalid tier (worst rate)
    }

    /// @notice Map credit score to tier index
    /// @param score Credit score 0–1000
    /// @return tier 0–3
    function getTierFromScore(uint256 score) internal pure returns (uint256 tier) {
        if (score >= 851) return 3;
        if (score >= 700) return 2;
        if (score >= 400) return 1;
        return 0;
    }
}
