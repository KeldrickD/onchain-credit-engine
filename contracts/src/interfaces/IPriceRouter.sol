// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./IPriceOracle.sol";

/// @title IPriceRouter
/// @notice Unified price source: Chainlink or SignedPriceOracle. Output always USD8.
interface IPriceRouter {
    enum Source {
        NONE,
        CHAINLINK,
        SIGNED
    }

    /// @notice Get price in USD with 8 decimals (Chainlink standard)
    /// @param asset Collateral token address
    /// @return priceUSD8 Price with 8 decimals
    /// @return updatedAt Timestamp of last update
    /// @return isStale True if price exceeds staleness threshold
    function getPriceUSD8(address asset)
        external
        view
        returns (uint256 priceUSD8, uint256 updatedAt, bool isStale);

    /// @notice Update signed oracle and return price (Option B: centralizes source logic)
    /// @param asset Collateral token address
    /// @param payload Signed price payload
    /// @param signature Oracle signature
    /// @return priceUSD8 Price with 8 decimals after update
    function updateSignedPriceAndGet(address asset, IPriceOracle.PricePayload calldata payload, bytes calldata signature)
        external
        returns (uint256 priceUSD8);

    /// @notice Get current source for an asset
    function getSource(address asset) external view returns (Source);

    /// @notice Get staleness period in seconds for an asset
    function getStalePeriod(address asset) external view returns (uint256);
}
