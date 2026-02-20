// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";

contract IssuerRegistryTest is Test {
    IssuerRegistry internal registry;
    address internal admin;
    address internal manager;
    address internal issuer;
    bytes32 internal constant TYPE_DSCR = keccak256("DSCR_BPS");

    function setUp() public {
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        issuer = makeAddr("issuer");

        vm.prank(admin);
        registry = new IssuerRegistry(admin);

        vm.prank(admin);
        registry.grantRole(registry.MANAGER_ROLE(), manager);
    }

    function test_SetIssuer_ByManager() public {
        vm.prank(manager);
        registry.setIssuer(issuer, true, 7_500, keccak256("meta"), "ipfs://issuer");

        (bool active, uint16 trustScoreBps, uint64 since,, string memory metadataURI) = registry.getIssuer(issuer);
        assertTrue(active);
        assertEq(trustScoreBps, 7_500);
        assertGt(since, 0);
        assertEq(metadataURI, "ipfs://issuer");
    }

    function test_SetIssuer_NonManagerReverts() public {
        vm.prank(makeAddr("not-manager"));
        vm.expectRevert();
        registry.setIssuer(issuer, true, 7_500, bytes32(0), "");
    }

    function test_SetIssuer_InvalidBpsReverts() public {
        vm.prank(manager);
        vm.expectRevert(IssuerRegistry.IssuerRegistry_InvalidBps.selector);
        registry.setIssuer(issuer, true, 10_001, bytes32(0), "");
    }

    function test_TrustedForType_FalseUntilConfigured() public {
        vm.prank(manager);
        registry.setIssuer(issuer, true, 8_000, bytes32(0), "");

        assertFalse(registry.isTrustedForType(issuer, TYPE_DSCR));

        vm.prank(manager);
        registry.setIssuerTypePermission(issuer, TYPE_DSCR, true);

        assertTrue(registry.isTrustedForType(issuer, TYPE_DSCR));
    }

    function test_MinTrustThresholdApplied() public {
        vm.startPrank(manager);
        registry.setIssuer(issuer, true, 6_500, bytes32(0), "");
        registry.setIssuerTypePermission(issuer, TYPE_DSCR, true);
        registry.setMinTrustScoreBpsForType(TYPE_DSCR, 7_000);
        vm.stopPrank();

        assertFalse(registry.isTrustedForType(issuer, TYPE_DSCR));

        vm.prank(manager);
        registry.setIssuerTrustScore(issuer, 7_100);
        assertTrue(registry.isTrustedForType(issuer, TYPE_DSCR));
    }
}
