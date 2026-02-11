// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20WithCallback
/// @notice ERC20 that calls back to recipient on transfer (reentrancy test)
contract MockERC20WithCallback is ERC20 {
    address public callbackTarget;

    constructor() ERC20("Callback Token", "CBT") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setCallbackTarget(address _target) external {
        callbackTarget = _target;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (callbackTarget != address(0) && to == callbackTarget && to.code.length > 0) {
            IReceiver(to).receiveCallback(from, value);
        }
    }
}

interface IReceiver {
    function receiveCallback(address from, uint256 amount) external;
}
