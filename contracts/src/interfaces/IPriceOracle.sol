// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    struct PricePayload {
        address asset;
        uint256 price;   // USDC decimals (6)
        uint256 timestamp;
        uint256 nonce;
    }

    function verifyPricePayload(PricePayload calldata payload, bytes calldata signature)
        external
        returns (bool);

    function verifyPricePayloadView(PricePayload calldata payload, bytes calldata signature)
        external
        view
        returns (bool);

    function getPrice(address asset) external view returns (uint256 price, uint256 lastUpdated);
}
