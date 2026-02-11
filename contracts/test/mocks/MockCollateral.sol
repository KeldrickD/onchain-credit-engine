// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockCollateral
/// @notice WETH-like collateral for tests. 18 decimals, mintable.
contract MockCollateral is ERC20 {
    constructor() ERC20("Mock Collateral", "mCOL") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
