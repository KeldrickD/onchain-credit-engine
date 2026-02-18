// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISubjectRegistry
/// @notice DID-lite registry for sponsor/entity/deal subject IDs.
interface ISubjectRegistry {
    event SubjectCreated(bytes32 indexed subjectId, address indexed controller, bytes32 indexed subjectType);
    event DelegateSet(bytes32 indexed subjectId, address indexed delegate, bool allowed);

    error SubjectRegistry_InvalidDelegate();
    error SubjectRegistry_SubjectNotFound();
    error SubjectRegistry_NotController();
    error SubjectRegistry_SubjectAlreadyExists();

    function createSubject(bytes32 subjectType, bytes32 salt) external returns (bytes32 subjectId);
    function setDelegate(bytes32 subjectId, address delegate, bool allowed) external;
    function isAuthorized(bytes32 subjectId, address caller) external view returns (bool);
    function controllerOf(bytes32 subjectId) external view returns (address);
    function subjectTypeOf(bytes32 subjectId) external view returns (bytes32);
    function controllerNonce(address controller) external view returns (uint256);
}
