// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceRouter} from "./interfaces/IPriceRouter.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PriceRouter
/// @notice Unified price source: Chainlink (production) or SignedPriceOracle (dev/staging).
///         Output always USD8 (Chainlink standard).
contract PriceRouter is IPriceRouter, Ownable {
    uint256 private constant USDC6_TO_USD8 = 100; // 8 - 6 decimals
    uint256 private constant DEFAULT_STALE_PERIOD = 3600; // 1 hour for chainlink

    struct AssetConfig {
        Source source;
        address chainlinkFeed;
        address signedOracle;
        uint256 stalePeriod;
    }
    mapping(address => AssetConfig) private configs;

    event ChainlinkFeedSet(address indexed asset, address feed);
    event SignedOracleSet(address indexed asset, address oracle);
    event SourceSet(address indexed asset, Source source);
    event StalePeriodSet(address indexed asset, uint256 seconds_);

    error PriceRouter_NoPrice();
    error PriceRouter_InvalidFeed();
    error PriceRouter_InvalidSource();
    error PriceRouter_InvalidAnswer();

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IPriceRouter
    function getPriceUSD8(address asset)
        external
        view
        override
        returns (uint256 priceUSD8, uint256 updatedAt, bool isStale)
    {
        AssetConfig memory cfg = configs[asset];
        if (cfg.source == Source.NONE) return (0, 0, true);

        if (cfg.source == Source.CHAINLINK) {
            if (cfg.chainlinkFeed == address(0)) return (0, 0, true);
            (priceUSD8, updatedAt) = _readChainlink(cfg.chainlinkFeed);
        } else {
            if (cfg.signedOracle == address(0)) return (0, 0, true);
            (priceUSD8, updatedAt) = _readSigned(cfg.signedOracle, asset);
        }

        uint256 staleThreshold = cfg.stalePeriod > 0 ? cfg.stalePeriod : DEFAULT_STALE_PERIOD;
        isStale = block.timestamp > updatedAt + staleThreshold;
    }

    /// @inheritdoc IPriceRouter
    function updateSignedPriceAndGet(address asset, IPriceOracle.PricePayload calldata payload, bytes calldata signature)
        external
        override
        returns (uint256 priceUSD8)
    {
        AssetConfig memory cfg = configs[asset];
        if (cfg.source != Source.SIGNED || cfg.signedOracle == address(0)) revert PriceRouter_InvalidSource();
        if (payload.asset != asset) revert PriceRouter_InvalidSource();

        IPriceOracle(cfg.signedOracle).verifyPricePayload(payload, signature);
        (priceUSD8,) = _readSigned(cfg.signedOracle, asset);
        if (priceUSD8 == 0) revert PriceRouter_NoPrice();
    }

    /// @inheritdoc IPriceRouter
    function getSource(address asset) external view override returns (Source) {
        return configs[asset].source;
    }

    /// @inheritdoc IPriceRouter
    function getStalePeriod(address asset) external view override returns (uint256) {
        uint256 p = configs[asset].stalePeriod;
        return p > 0 ? p : DEFAULT_STALE_PERIOD;
    }

    function setChainlinkFeed(address asset, address feed) external onlyOwner {
        configs[asset].chainlinkFeed = feed;
        emit ChainlinkFeedSet(asset, feed);
    }

    function setSignedOracle(address asset, address oracle) external onlyOwner {
        configs[asset].signedOracle = oracle;
        emit SignedOracleSet(asset, oracle);
    }

    function setSource(address asset, Source source) external onlyOwner {
        configs[asset].source = source;
        emit SourceSet(asset, source);
    }

    function setStalePeriod(address asset, uint256 seconds_) external onlyOwner {
        configs[asset].stalePeriod = seconds_;
        emit StalePeriodSet(asset, seconds_);
    }

    function getChainlinkFeed(address asset) external view returns (address) {
        return configs[asset].chainlinkFeed;
    }

    function getSignedOracle(address asset) external view returns (address) {
        return configs[asset].signedOracle;
    }

    uint256 private constant TARGET_DECIMALS = 8;

    function _readChainlink(address feed) internal view returns (uint256 priceUSD8, uint256 updatedAt) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt_,
            uint80 answeredInRound
        ) = IAggregatorV3(feed).latestRoundData();

        if (answer <= 0) revert PriceRouter_InvalidAnswer();
        if (updatedAt_ == 0) return (0, 0);
        if (answeredInRound == 0 || answeredInRound < roundId) return (0, 0);

        uint8 feedDecimals = IAggregatorV3(feed).decimals();
        if (feedDecimals == TARGET_DECIMALS) {
            priceUSD8 = uint256(answer);
        } else if (feedDecimals < TARGET_DECIMALS) {
            priceUSD8 = uint256(answer) * (10 ** (TARGET_DECIMALS - feedDecimals));
        } else {
            priceUSD8 = uint256(answer) / (10 ** (feedDecimals - TARGET_DECIMALS));
        }
        updatedAt = updatedAt_;
    }

    /// @dev SignedPriceOracle stores price in USDC6. Scale to USD8: multiply by 100.
    function _readSigned(address oracle, address asset) internal view returns (uint256 priceUSD8, uint256 updatedAt) {
        (uint256 priceUSDC6, uint256 lastUpdated) = IPriceOracle(oracle).getPrice(asset);
        if (priceUSDC6 == 0) return (0, lastUpdated);
        priceUSD8 = priceUSDC6 * USDC6_TO_USD8;
        updatedAt = lastUpdated;
    }
}
