// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISubjectRegistry} from "./interfaces/ISubjectRegistry.sol";

/// @title SubjectRegistry
/// @notice DID-lite identity layer for sponsors/entities/deals represented as bytes32 subject IDs.
contract SubjectRegistry is ISubjectRegistry {
    mapping(bytes32 => address) private _controllerBySubject;
    mapping(bytes32 => bytes32) private _subjectTypeById;
    mapping(bytes32 => mapping(address => bool)) private _delegates;
    mapping(address => uint256) public controllerNonce;

    /// @inheritdoc ISubjectRegistry
    function createSubject(bytes32 subjectType, bytes32 salt) public override returns (bytes32 subjectId) {
        subjectId = keccak256(abi.encode(subjectType, msg.sender, salt));
        if (_controllerBySubject[subjectId] != address(0)) {
            revert SubjectRegistry_SubjectAlreadyExists();
        }

        _controllerBySubject[subjectId] = msg.sender;
        _subjectTypeById[subjectId] = subjectType;
        controllerNonce[msg.sender] += 1;

        emit SubjectCreated(subjectId, msg.sender, subjectType);
    }

    /// @inheritdoc ISubjectRegistry
    function createSubjectWithNonce(bytes32 subjectType) external override returns (bytes32 subjectId) {
        bytes32 salt = bytes32(controllerNonce[msg.sender]);
        return createSubject(subjectType, salt);
    }

    /// @inheritdoc ISubjectRegistry
    function setDelegate(bytes32 subjectId, address delegate, bool allowed) external override {
        address controller = _controllerBySubject[subjectId];
        if (controller == address(0)) revert SubjectRegistry_SubjectNotFound();
        if (msg.sender != controller) revert SubjectRegistry_NotController();
        if (delegate == address(0)) revert SubjectRegistry_InvalidDelegate();

        _delegates[subjectId][delegate] = allowed;
        emit DelegateSet(subjectId, delegate, allowed);
    }

    /// @inheritdoc ISubjectRegistry
    function isAuthorized(bytes32 subjectId, address caller) external view override returns (bool) {
        address controller = _controllerBySubject[subjectId];
        return controller != address(0) && (caller == controller || _delegates[subjectId][caller]);
    }

    /// @inheritdoc ISubjectRegistry
    function controllerOf(bytes32 subjectId) external view override returns (address) {
        return _controllerBySubject[subjectId];
    }

    /// @inheritdoc ISubjectRegistry
    function subjectTypeOf(bytes32 subjectId) external view override returns (bytes32) {
        return _subjectTypeById[subjectId];
    }
}
