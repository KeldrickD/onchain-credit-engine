// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TreasuryVault
/// @notice Custody + accounting for USDC. Dumb vault: no interest, shares, or loan logic.
/// @dev Permission boundary for LoanEngine; transferToBorrower/pullFromBorrower are onlyLoanEngine
contract TreasuryVault is ITreasuryVault, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IERC20 public immutable usdc;

    /// @notice LoanEngine address; only it can call transferToBorrower / pullFromBorrower
    address public loanEngine;

    mapping(address => uint256) private balances;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event LoanEngineSet(address indexed oldEngine, address indexed newEngine);
    event TransferredToBorrower(address indexed borrower, uint256 amount);
    event PulledFromBorrower(address indexed borrower, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error TreasuryVault_InsufficientBalance();
    error TreasuryVault_ZeroAmount();
    error TreasuryVault_Unauthorized();
    error TreasuryVault_InvalidAddress();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyLoanEngine() {
        if (msg.sender != loanEngine) revert TreasuryVault_Unauthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _usdc USDC token address
    /// @param _owner Owner (can set LoanEngine)
    constructor(address _usdc, address _owner) Ownable(_owner) {
        if (_usdc == address(0)) revert TreasuryVault_InvalidAddress();
        usdc = IERC20(_usdc);
    }

    // -------------------------------------------------------------------------
    // External
    // -------------------------------------------------------------------------

    /// @inheritdoc ITreasuryVault
    function deposit(uint256 amount) external override {
        if (amount == 0) revert TreasuryVault_ZeroAmount();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;

        emit Deposited(msg.sender, amount);
    }

    /// @inheritdoc ITreasuryVault
    function withdraw(uint256 amount) external override nonReentrant {
        if (amount == 0) revert TreasuryVault_ZeroAmount();
        if (balances[msg.sender] < amount) revert TreasuryVault_InsufficientBalance();

        balances[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @inheritdoc ITreasuryVault
    function balanceOf(address user) external view override returns (uint256) {
        return balances[user];
    }

    /// @inheritdoc ITreasuryVault
    function setLoanEngine(address _loanEngine) external override onlyOwner {
        address old = loanEngine;
        loanEngine = _loanEngine;
        emit LoanEngineSet(old, _loanEngine);
    }

    /// @inheritdoc ITreasuryVault
    function transferToBorrower(address borrower, uint256 amount) external override onlyLoanEngine {
        if (amount == 0) revert TreasuryVault_ZeroAmount();
        if (borrower == address(0)) revert TreasuryVault_InvalidAddress();

        usdc.safeTransfer(borrower, amount);
        emit TransferredToBorrower(borrower, amount);
    }

    /// @inheritdoc ITreasuryVault
    function pullFromBorrower(address borrower, uint256 amount) external override onlyLoanEngine {
        if (amount == 0) revert TreasuryVault_ZeroAmount();
        if (borrower == address(0)) revert TreasuryVault_InvalidAddress();

        usdc.safeTransferFrom(borrower, address(this), amount);
        emit PulledFromBorrower(borrower, amount);
    }

    /// @notice Total USDC held by vault (for transparency)
    function totalUsdcBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
