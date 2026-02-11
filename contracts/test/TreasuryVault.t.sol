// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract TreasuryVaultTest is Test {
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event LoanEngineSet(address indexed oldEngine, address indexed newEngine);
    TreasuryVault public vault;
    MockUSDC public usdc;

    address public owner;
    address public user;
    address public loanEngine;
    address public borrower;

    uint256 public constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDC (6 decimals)

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        loanEngine = makeAddr("loanEngine");
        borrower = makeAddr("borrower");

        usdc = new MockUSDC();
        usdc.mint(user, 10_000e6);

        vm.prank(owner);
        vault = new TreasuryVault(address(usdc), owner);
    }

    // -------------------------------------------------------------------------
    // Deposits
    // -------------------------------------------------------------------------

    function test_Deposit_IncreasesUserBalanceAndVaultUsdc() public {
        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(vault.balanceOf(user), DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(user), 10_000e6 - DEPOSIT_AMOUNT);
    }

    function test_Deposit_EmitsDeposited() public {
        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit Deposited(user, DEPOSIT_AMOUNT);

        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_Deposit_ZeroAmount_Reverts() public {
        vm.prank(user);
        vm.expectRevert(TreasuryVault.TreasuryVault_ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_Deposit_RequiresApproval() public {
        vm.prank(user);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT); // No approve
    }

    function test_Deposit_MultipleIncrementsBalance() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 2 * DEPOSIT_AMOUNT);

        vault.deposit(DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);

        assertEq(vault.balanceOf(user), 2 * DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(vault)), 2 * DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Withdrawals
    // -------------------------------------------------------------------------

    function test_Withdraw_DecreasesBalanceAndTransfersUsdc() public {
        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 balBefore = usdc.balanceOf(user);

        vm.prank(user);
        vault.withdraw(DEPOSIT_AMOUNT);

        assertEq(vault.balanceOf(user), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(user), balBefore + DEPOSIT_AMOUNT);
    }

    function test_Withdraw_MoreThanBalance_Reverts() public {
        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(TreasuryVault.TreasuryVault_InsufficientBalance.selector);
        vault.withdraw(DEPOSIT_AMOUNT + 1);
    }

    function test_Withdraw_ZeroAmount_Reverts() public {
        vm.prank(user);
        vm.expectRevert(TreasuryVault.TreasuryVault_ZeroAmount.selector);
        vault.withdraw(0);
    }

    function test_Withdraw_EmitsWithdrawn() public {
        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(user, DEPOSIT_AMOUNT);

        vm.prank(user);
        vault.withdraw(DEPOSIT_AMOUNT);
    }

    // Reentrancy: TreasuryVault uses nonReentrant on withdraw. CEI + guard.

    // -------------------------------------------------------------------------
    // LoanEngine permissions
    // -------------------------------------------------------------------------

    function test_SetLoanEngine_OnlyOwner() public {
        vm.prank(owner);
        vault.setLoanEngine(loanEngine);
        assertEq(vault.loanEngine(), loanEngine);
    }

    function test_SetLoanEngine_NotOwner_Reverts() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setLoanEngine(loanEngine);
    }

    function test_SetLoanEngine_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit LoanEngineSet(address(0), loanEngine);

        vm.prank(owner);
        vault.setLoanEngine(loanEngine);
    }

    function test_TransferToBorrower_OnlyLoanEngine() public {
        vm.prank(owner);
        vault.setLoanEngine(loanEngine);

        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 amount = 500e6;
        vm.prank(loanEngine);
        vault.transferToBorrower(borrower, amount);

        assertEq(usdc.balanceOf(borrower), amount);
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT - amount);
        assertEq(vault.balanceOf(user), DEPOSIT_AMOUNT); // Internal balance unchanged
    }

    function test_TransferToBorrower_NotLoanEngine_Reverts() public {
        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(TreasuryVault.TreasuryVault_Unauthorized.selector);
        vault.transferToBorrower(borrower, 100e6);
    }

    function test_TransferToBorrower_ReducesVaultUsdc_IncreasesBorrowerWallet() public {
        vm.prank(owner);
        vault.setLoanEngine(loanEngine);

        vm.startPrank(user);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 borrowerBefore = usdc.balanceOf(borrower);
        uint256 vaultBefore = usdc.balanceOf(address(vault));

        vm.prank(loanEngine);
        vault.transferToBorrower(borrower, 200e6);

        assertEq(usdc.balanceOf(borrower), borrowerBefore + 200e6);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore - 200e6);
    }

    function test_PullFromBorrower_OnlyLoanEngine() public {
        vm.prank(owner);
        vault.setLoanEngine(loanEngine);

        usdc.mint(borrower, 300e6);
        vm.prank(borrower);
        usdc.approve(address(vault), 300e6);

        uint256 vaultBefore = usdc.balanceOf(address(vault));

        vm.prank(loanEngine);
        vault.pullFromBorrower(borrower, 300e6);

        assertEq(usdc.balanceOf(borrower), 0);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore + 300e6);
    }

    function test_PullFromBorrower_NotLoanEngine_Reverts() public {
        usdc.mint(borrower, 100e6);
        vm.prank(borrower);
        usdc.approve(address(vault), 100e6);

        vm.prank(user);
        vm.expectRevert(TreasuryVault.TreasuryVault_Unauthorized.selector);
        vault.pullFromBorrower(borrower, 100e6);
    }
}