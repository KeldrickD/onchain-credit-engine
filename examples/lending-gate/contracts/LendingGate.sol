// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICreditRegistry {
    struct CreditProfile {
        uint256 score;
        uint256 riskTier;
        uint256 lastUpdated;
        bytes32 modelId;
        uint16 confidenceBps;
        bytes32 reasonsHash;
        bytes32 evidenceHash;
    }

    function getCreditProfile(address user) external view returns (CreditProfile memory);
    function getProfile(bytes32 key) external view returns (CreditProfile memory);
}

/// @title LendingGate
/// @notice Minimal OCX consumer example for wallet + subject-key credit gating.
contract LendingGate {
    ICreditRegistry public immutable creditRegistry;
    address public owner;

    uint256 public minScore;
    uint256 public maxTier;
    bool public useConfidence;
    uint16 public minConfidenceBps;

    error NotOwner();
    error NotEligible(uint256 score, uint256 tier, uint16 confidenceBps);

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event GateConfigUpdated(uint256 minScore, uint256 maxTier, bool useConfidence, uint16 minConfidenceBps);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address creditRegistry_, uint256 minScore_, uint256 maxTier_) {
        creditRegistry = ICreditRegistry(creditRegistry_);
        owner = msg.sender;
        minScore = minScore_;
        maxTier = maxTier_;
    }

    function setOwner(address newOwner) external onlyOwner {
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    function setGateConfig(uint256 minScore_, uint256 maxTier_, bool useConfidence_, uint16 minConfidenceBps_)
        external
        onlyOwner
    {
        minScore = minScore_;
        maxTier = maxTier_;
        useConfidence = useConfidence_;
        minConfidenceBps = minConfidenceBps_;
        emit GateConfigUpdated(minScore_, maxTier_, useConfidence_, minConfidenceBps_);
    }

    function canBorrowWallet(address user) public view returns (bool) {
        return _isEligible(creditRegistry.getCreditProfile(user));
    }

    function canBorrowKey(bytes32 subjectKey) public view returns (bool) {
        return _isEligible(creditRegistry.getProfile(subjectKey));
    }

    function requireBorrowableWallet(address user) external view {
        ICreditRegistry.CreditProfile memory profile = creditRegistry.getCreditProfile(user);
        if (!_isEligible(profile)) revert NotEligible(profile.score, profile.riskTier, profile.confidenceBps);
    }

    function requireBorrowableKey(bytes32 subjectKey) external view {
        ICreditRegistry.CreditProfile memory profile = creditRegistry.getProfile(subjectKey);
        if (!_isEligible(profile)) revert NotEligible(profile.score, profile.riskTier, profile.confidenceBps);
    }

    function _isEligible(ICreditRegistry.CreditProfile memory profile) internal view returns (bool) {
        if (profile.score < minScore) return false;
        if (profile.riskTier > maxTier) return false;
        if (useConfidence && profile.confidenceBps < minConfidenceBps) return false;
        return true;
    }
}

