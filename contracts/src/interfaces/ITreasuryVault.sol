// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasuryVault {
    /// @notice Deposit USDC into the vault; increases internal balance
    /// @param amount Amount to deposit
    function deposit(uint256 amount) external;

    /// @notice Withdraw USDC from the vault; decreases internal balance
    /// @param amount Amount to withdraw
    function withdraw(uint256 amount) external;

    /// @notice User's internal vault balance (deposits only)
    /// @param user Address to query
    function balanceOf(address user) external view returns (uint256);

    /// @notice Set the LoanEngine address (owner-only). Enables protocol lending.
    /// @param loanEngine Address of the LoanEngine contract
    function setLoanEngine(address loanEngine) external;

    /// @notice Set the LiquidationManager (owner-only). Can pullFromBorrower for liquidations.
    /// @param liquidationManager Address of the LiquidationManager contract
    function setLiquidationManager(address liquidationManager) external;

    /// @notice Transfer vault USDC to a borrower (onlyLoanEngine). Protocol-controlled distribution.
    /// @dev Does not affect internal balances; moves from aggregate vault liquidity.
    /// @param borrower Recipient address
    /// @param amount Amount to transfer
    function transferToBorrower(address borrower, uint256 amount) external;

    /// @notice Pull USDC from a borrower into the vault (onlyLoanEngine). Useful for repayments.
    /// @param borrower Address to pull from
    /// @param amount Amount to pull
    function pullFromBorrower(address borrower, uint256 amount) external;
}
