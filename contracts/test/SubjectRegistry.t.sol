// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubjectRegistry} from "../src/SubjectRegistry.sol";
import {ISubjectRegistry} from "../src/interfaces/ISubjectRegistry.sol";

contract SubjectRegistryTest is Test {
    SubjectRegistry public registry;
    address public controller;
    address public delegate;
    address public other;

    bytes32 public constant DEAL = keccak256("DEAL");
    bytes32 public constant ENTITY = keccak256("ENTITY");

    function setUp() public {
        registry = new SubjectRegistry();
        controller = makeAddr("controller");
        delegate = makeAddr("delegate");
        other = makeAddr("other");
    }

    function test_CreateSubject_SetsControllerAndType() public {
        bytes32 salt = keccak256("deal-1");
        bytes32 expectedId = keccak256(abi.encode(DEAL, controller, salt));

        vm.prank(controller);
        bytes32 id = registry.createSubject(DEAL, salt);

        assertEq(id, expectedId);
        assertEq(registry.controllerOf(id), controller);
        assertEq(registry.subjectTypeOf(id), DEAL);
        assertEq(registry.controllerNonce(controller), 1);
    }

    function test_CreateSubject_SameSaltSameController_Reverts() public {
        bytes32 salt = keccak256("dup");

        vm.prank(controller);
        registry.createSubject(DEAL, salt);

        vm.prank(controller);
        vm.expectRevert(ISubjectRegistry.SubjectRegistry_SubjectAlreadyExists.selector);
        registry.createSubject(DEAL, salt);
    }

    function test_SetDelegate_ControllerOnly() public {
        bytes32 salt = keccak256("delegate");
        vm.prank(controller);
        bytes32 id = registry.createSubject(ENTITY, salt);

        vm.prank(other);
        vm.expectRevert(ISubjectRegistry.SubjectRegistry_NotController.selector);
        registry.setDelegate(id, delegate, true);

        vm.prank(controller);
        registry.setDelegate(id, delegate, true);
        assertTrue(registry.isAuthorized(id, delegate));
    }

    function test_SetDelegate_ZeroAddress_Reverts() public {
        vm.prank(controller);
        bytes32 id = registry.createSubject(DEAL, keccak256("z"));

        vm.prank(controller);
        vm.expectRevert(ISubjectRegistry.SubjectRegistry_InvalidDelegate.selector);
        registry.setDelegate(id, address(0), true);
    }

    function test_CreateSubjectWithNonce_DeterministicUniqueIds() public {
        vm.prank(controller);
        bytes32 id1 = registry.createSubjectWithNonce(DEAL);
        vm.prank(controller);
        bytes32 id2 = registry.createSubjectWithNonce(DEAL);
        vm.prank(controller);
        bytes32 id3 = registry.createSubjectWithNonce(ENTITY);

        assertNotEq(id1, id2);
        assertNotEq(id2, id3);
        assertEq(registry.controllerOf(id1), controller);
        assertEq(registry.controllerOf(id2), controller);
        assertEq(registry.controllerNonce(controller), 3);
    }

    function test_IsAuthorized_ControllerAndDelegate() public {
        vm.prank(controller);
        bytes32 id = registry.createSubject(DEAL, keccak256("auth"));

        assertTrue(registry.isAuthorized(id, controller));
        assertFalse(registry.isAuthorized(id, delegate));

        vm.prank(controller);
        registry.setDelegate(id, delegate, true);
        assertTrue(registry.isAuthorized(id, delegate));

        vm.prank(controller);
        registry.setDelegate(id, delegate, false);
        assertFalse(registry.isAuthorized(id, delegate));
    }
}
