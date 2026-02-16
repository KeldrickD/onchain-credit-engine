// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILoanEngine} from "../../src/interfaces/ILoanEngine.sol";
import {IRiskOracle} from "../../src/interfaces/IRiskOracle.sol";

/// @notice Mock LoanEngine for RiskEngineV2 unit tests
contract MockLoanEngineForRisk is ILoanEngine {
    mapping(address => ILoanEngine.LoanPosition) public positions;
    mapping(address => uint64) public lastRepayAt;
    mapping(address => uint32) public liquidationCount;
    mapping(address => mapping(address => uint256)) public maxBorrows;

    function setPosition(
        address user,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 principalAmount,
        uint256 ltvBps,
        uint256 interestRateBps
    ) external {
        positions[user] = ILoanEngine.LoanPosition({
            collateralAsset: collateralAsset,
            collateralAmount: collateralAmount,
            principalAmount: principalAmount,
            openedAt: block.timestamp,
            ltvBps: ltvBps,
            interestRateBps: interestRateBps
        });
    }

    function setLastRepayAt(address user, uint64 timestamp) external {
        lastRepayAt[user] = timestamp;
    }

    function setLiquidationCount(address user, uint32 count) external {
        liquidationCount[user] = count;
    }

    function setMaxBorrow(address user, address asset, uint256 max) external {
        maxBorrows[user][asset] = max;
    }

    function getTerms(address) external pure returns (ILoanEngine.LoanTerms memory) {
        return ILoanEngine.LoanTerms({ltvBps: 7500, interestRateBps: 700});
    }

    function getPosition(address user) external view returns (ILoanEngine.LoanPosition memory) {
        return positions[user];
    }

    function getCollateralBalance(address, address) external pure returns (uint256) {
        return 0;
    }

    function getPositionCollateralAsset(address user) external view returns (address) {
        return positions[user].collateralAsset;
    }

    function getMaxBorrow(address user, address asset) external view returns (uint256) {
        return maxBorrows[user][asset];
    }

    function depositCollateral(address, uint256) external pure {}
    function withdrawCollateral(address, uint256) external pure {}
    function openLoan(address, uint256, IRiskOracle.RiskPayload calldata, bytes calldata) external pure {}
    function repay(uint256) external pure {}
    function liquidationRepay(address, uint256) external pure {}
    function seizeCollateral(address, address, uint256) external pure {}
}
