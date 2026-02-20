// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDealFactory
/// @notice Example: first-class deal subject + metadata + capital request (built on SubjectRegistry)
interface IDealFactory {
    struct Deal {
        bytes32 dealId;
        address sponsor;
        bytes32 dealType;         // keccak256("SFR"), "MF", "DEV", etc.
        string metadataURI;       // ipfs://... (deal deck, etc.)
        address collateralAsset; // WETH/WBTC; later tokenized real world
        uint256 requestedUSDC6;
        uint64 createdAt;
        bool active;
    }

    event DealCreated(
        bytes32 indexed dealId,
        address indexed sponsor,
        bytes32 indexed dealType,
        string metadataURI,
        address collateralAsset,
        uint256 requestedUSDC6,
        uint64 createdAt
    );
    event DealMetadataUpdated(bytes32 indexed dealId, string metadataURI);
    event DealDeactivated(bytes32 indexed dealId, address indexed by);

    error DealFactory_NotAuthorized();
    error DealFactory_DealNotFound();
    error DealFactory_DealInactive();

    function createDeal(
        bytes32 dealType,
        string calldata metadataURI,
        address collateralAsset,
        uint256 requestedUSDC6
    ) external returns (bytes32 dealId);

    function setDealMetadata(bytes32 dealId, string calldata metadataURI) external;
    function deactivateDeal(bytes32 dealId) external;
    function getDeal(bytes32 dealId) external view returns (Deal memory);
}
