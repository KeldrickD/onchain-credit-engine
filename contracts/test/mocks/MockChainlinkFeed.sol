// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";

/// @title MockChainlinkFeed
/// @notice Test double for Chainlink price feeds
contract MockChainlinkFeed is IAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;
    uint8 private _decimals;

    constructor(int256 _initialPrice) {
        answer = _initialPrice;
        updatedAt = block.timestamp;
        roundId = 1;
        _decimals = 8;
    }

    /// @dev For tests: change feed decimals (e.g. to test normalization)
    function setDecimals(uint8 d) external {
        _decimals = d;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 _roundId,
            int256 _answer,
            uint256 _startedAt,
            uint256 _updatedAt,
            uint80 _answeredInRound
        )
    {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function setPrice(int256 _price) external {
        answer = _price;
        updatedAt = block.timestamp;
        roundId++;
    }

    function setPriceAndTime(int256 _price, uint256 _updatedAt) external {
        answer = _price;
        updatedAt = _updatedAt;
        roundId++;
    }
}
