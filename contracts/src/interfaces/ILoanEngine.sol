// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRiskOracle} from "./IRiskOracle.sol";

interface ILoanEngine {
    struct LoanTerms {
        uint256 ltvBps;
        uint256 interestRateBps;
    }

    struct LoanPosition {
        address collateralAsset;
        uint256 collateralAmount;
        uint256 principalAmount;
        uint256 openedAt;
        uint256 ltvBps;
        uint256 interestRateBps;
    }

    function depositCollateral(address asset, uint256 amount) external;
    function withdrawCollateral(address asset, uint256 amount) external;

    function openLoan(
        address asset,
        uint256 borrowAmountUSDC6,
        IRiskOracle.RiskPayload calldata payload,
        bytes calldata signature
    ) external;

    function repay(uint256 amount) external;

    function getTerms(address user) external view returns (LoanTerms memory);
    function getPosition(address user) external view returns (LoanPosition memory);
    function getCollateralBalance(address user, address asset) external view returns (uint256);
    function getPositionCollateralAsset(address user) external view returns (address);
    function getMaxBorrow(address user, address asset) external view returns (uint256);
    function lastRepayAt(address user) external view returns (uint64);
    function liquidationCount(address user) external view returns (uint32);
    function liquidationRepay(address borrower, uint256 amount) external;
    function seizeCollateral(address borrower, address to, uint256 amount) external;
}
