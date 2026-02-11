// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LiquidationManager} from "../../src/LiquidationManager.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Attacker contract: attempts reentrancy when receiving seized collateral
contract ReentrancyLiquidator {
    LiquidationManager public liqManager;
    IERC20 public usdc;
    address public vault;
    address public borrower;

    constructor(address _liqManager, address _usdc, address _vault) {
        liqManager = LiquidationManager(payable(_liqManager));
        usdc = IERC20(_usdc);
        vault = _vault;
    }

    function setBorrower(address _borrower) external {
        borrower = _borrower;
    }

    function liquidate(
        uint256 repayAmount,
        IPriceOracle.PricePayload calldata payload,
        bytes calldata sig
    ) external {
        usdc.approve(vault, repayAmount);
        liqManager.liquidate(borrower, repayAmount, payload, sig);
    }

    function receiveCallback(address, uint256) external {
        liqManager.liquidate(borrower, 1, IPriceOracle.PricePayload({
            asset: address(0),
            price: 0,
            timestamp: 0,
            nonce: 999
        }), "");
    }
}
