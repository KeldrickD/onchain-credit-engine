// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:", address(usdc));

        TreasuryVault vault = new TreasuryVault(address(usdc), msg.sender);
        console.log("TreasuryVault:", address(vault));

        vm.stopBroadcast();
    }
}
