// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract HashConsistencyTest is Test {
    function test_Bytes32ArrayHash_MatchesExpectedAbiEncodeHash() public pure {
        bytes32[] memory arr = new bytes32[](3);
        arr[0] = bytes32(uint256(0x1111111111111111111111111111111111111111111111111111111111111111));
        arr[1] = bytes32(uint256(0x2222222222222222222222222222222222222222222222222222222222222222));
        arr[2] = bytes32(uint256(0x3333333333333333333333333333333333333333333333333333333333333333));

        bytes32 solidityHash = keccak256(abi.encode(arr));

        // Computed offchain with viem:
        // keccak256(encodeAbiParameters([{ type: "bytes32[]" }], [arr]))
        bytes32 expectedOffchainHash =
            0xb33141e287cdbb973ab6ab9cbd034a9f5772a7a2abd29f3b67efbbb90c107c7f;

        assertEq(solidityHash, expectedOffchainHash, "Solidity/offchain array hash mismatch");
    }
}
