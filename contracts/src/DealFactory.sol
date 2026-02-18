// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDealFactory} from "./interfaces/IDealFactory.sol";
import {ISubjectRegistry} from "./interfaces/ISubjectRegistry.sol";

/// @title DealFactory
/// @notice Creates first-class Deal subjects (sponsor + metadata + capital request) for CapitalMethod packaging
contract DealFactory is IDealFactory {
    ISubjectRegistry public immutable subjectRegistry;

    mapping(bytes32 => Deal) private _deals;

    constructor(address _subjectRegistry) {
        subjectRegistry = ISubjectRegistry(_subjectRegistry);
    }

    /// @inheritdoc IDealFactory
    function createDeal(
        bytes32 dealType,
        string calldata metadataURI,
        address collateralAsset,
        uint256 requestedUSDC6
    ) external override returns (bytes32 dealId) {
        dealId = subjectRegistry.createSubjectWithNonce(dealType);

        _deals[dealId] = Deal({
            dealId: dealId,
            sponsor: msg.sender,
            dealType: dealType,
            metadataURI: metadataURI,
            collateralAsset: collateralAsset,
            requestedUSDC6: requestedUSDC6,
            createdAt: uint64(block.timestamp),
            active: true
        });

        emit DealCreated(
            dealId,
            msg.sender,
            dealType,
            metadataURI,
            collateralAsset,
            requestedUSDC6,
            uint64(block.timestamp)
        );
    }

    /// @inheritdoc IDealFactory
    function setDealMetadata(bytes32 dealId, string calldata metadataURI) external override {
        Deal storage d = _deals[dealId];
        if (d.sponsor == address(0)) revert DealFactory_DealNotFound();
        if (!d.active) revert DealFactory_DealInactive();
        if (!subjectRegistry.isAuthorized(dealId, msg.sender)) revert DealFactory_NotAuthorized();

        d.metadataURI = metadataURI;
        emit DealMetadataUpdated(dealId, metadataURI);
    }

    /// @inheritdoc IDealFactory
    function deactivateDeal(bytes32 dealId) external override {
        Deal storage d = _deals[dealId];
        if (d.sponsor == address(0)) revert DealFactory_DealNotFound();
        if (!subjectRegistry.isAuthorized(dealId, msg.sender)) revert DealFactory_NotAuthorized();

        d.active = false;
        emit DealDeactivated(dealId, msg.sender);
    }

    /// @inheritdoc IDealFactory
    function getDeal(bytes32 dealId) external view override returns (Deal memory) {
        return _deals[dealId];
    }
}
