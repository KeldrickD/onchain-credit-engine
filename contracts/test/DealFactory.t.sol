// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DealFactory} from "../src/examples/DealFactory.sol";
import {SubjectRegistry} from "../src/SubjectRegistry.sol";
import {IDealFactory} from "../src/examples/IDealFactory.sol";
import {ISubjectRegistry} from "../src/interfaces/ISubjectRegistry.sol";

contract DealFactoryTest is Test {
    DealFactory public factory;
    SubjectRegistry public subjectRegistry;

    address public sponsor;
    address public other;
    address public delegate;

    bytes32 public constant SFR = keccak256("SFR");
    bytes32 public constant MF = keccak256("MF");
    bytes32 public constant DEV = keccak256("DEV");

    address public constant WETH = address(0x1234);
    uint256 public constant REQUESTED = 500_000e6;

    function setUp() public {
        subjectRegistry = new SubjectRegistry();
        factory = new DealFactory(address(subjectRegistry));

        sponsor = makeAddr("sponsor");
        other = makeAddr("other");
        delegate = makeAddr("delegate");
    }

    function test_CreateDeal_StoresDealAndEmits() public {
        vm.prank(sponsor);
        bytes32 dealId = factory.createDeal(
            SFR,
            "ipfs://QmDeal1",
            WETH,
            REQUESTED
        );

        assertNotEq(dealId, bytes32(0));
        assertEq(subjectRegistry.controllerOf(dealId), address(factory));
        assertTrue(subjectRegistry.isAuthorized(dealId, sponsor));
        assertEq(subjectRegistry.subjectTypeOf(dealId), SFR);

        IDealFactory.Deal memory d = factory.getDeal(dealId);
        assertEq(d.dealId, dealId);
        assertEq(d.sponsor, sponsor);
        assertEq(d.dealType, SFR);
        assertEq(d.metadataURI, "ipfs://QmDeal1");
        assertEq(d.collateralAsset, WETH);
        assertEq(d.requestedUSDC6, REQUESTED);
        assertTrue(d.active);
        assertGt(d.createdAt, 0);
    }

    function test_CreateDeal_SequentialDeals_DifferentIds() public {
        vm.startPrank(sponsor);

        bytes32 id1 = factory.createDeal(SFR, "ipfs://1", WETH, 100e6);
        bytes32 id2 = factory.createDeal(MF, "ipfs://2", WETH, 200e6);
        bytes32 id3 = factory.createDeal(DEV, "ipfs://3", address(0), 300e6);

        assertNotEq(id1, id2);
        assertNotEq(id2, id3);
        assertEq(factory.getDeal(id1).metadataURI, "ipfs://1");
        assertEq(factory.getDeal(id2).metadataURI, "ipfs://2");
        assertEq(factory.getDeal(id3).requestedUSDC6, 300e6);
        vm.stopPrank();
    }

    function test_SetDealMetadata_SponsorOnly() public {
        vm.prank(sponsor);
        bytes32 dealId = factory.createDeal(SFR, "ipfs://old", WETH, REQUESTED);

        vm.prank(other);
        vm.expectRevert(IDealFactory.DealFactory_NotAuthorized.selector);
        factory.setDealMetadata(dealId, "ipfs://hack");

        vm.prank(sponsor);
        factory.setDealMetadata(dealId, "ipfs://new");

        assertEq(factory.getDeal(dealId).metadataURI, "ipfs://new");
    }

    function test_SetDealMetadata_DelegateCanUpdate() public {
        vm.prank(sponsor);
        bytes32 dealId = factory.createDeal(SFR, "ipfs://old", WETH, REQUESTED);

        vm.prank(sponsor);
        factory.setDealDelegate(dealId, delegate, true);

        vm.prank(delegate);
        factory.setDealMetadata(dealId, "ipfs://by-delegate");

        assertEq(factory.getDeal(dealId).metadataURI, "ipfs://by-delegate");
    }

    function test_SetDealMetadata_DealNotFound_Reverts() public {
        vm.prank(sponsor);
        vm.expectRevert(IDealFactory.DealFactory_DealNotFound.selector);
        factory.setDealMetadata(keccak256("nonexistent"), "ipfs://x");
    }

    function test_DeactivateDeal_SponsorOnly() public {
        vm.prank(sponsor);
        bytes32 dealId = factory.createDeal(SFR, "ipfs://x", WETH, REQUESTED);

        vm.prank(other);
        vm.expectRevert(IDealFactory.DealFactory_NotAuthorized.selector);
        factory.deactivateDeal(dealId);

        vm.prank(sponsor);
        factory.deactivateDeal(dealId);

        assertFalse(factory.getDeal(dealId).active);
    }

    function test_DeactivateDeal_DelegateCanDeactivate() public {
        vm.prank(sponsor);
        bytes32 dealId = factory.createDeal(SFR, "ipfs://x", WETH, REQUESTED);
        vm.prank(sponsor);
        factory.setDealDelegate(dealId, delegate, true);

        vm.prank(delegate);
        factory.deactivateDeal(dealId);

        assertFalse(factory.getDeal(dealId).active);
    }

    function test_SetDealMetadata_AfterDeactivate_Reverts() public {
        vm.prank(sponsor);
        bytes32 dealId = factory.createDeal(SFR, "ipfs://x", WETH, REQUESTED);
        vm.prank(sponsor);
        factory.deactivateDeal(dealId);

        vm.prank(sponsor);
        vm.expectRevert(IDealFactory.DealFactory_DealInactive.selector);
        factory.setDealMetadata(dealId, "ipfs://y");
    }

    function test_GetDeal_Nonexistent_ReturnsEmpty() public {
        IDealFactory.Deal memory d = factory.getDeal(keccak256("none"));
        assertEq(d.sponsor, address(0));
        assertEq(d.dealId, bytes32(0));
    }
}
