// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRiskEngineV2} from "./interfaces/IRiskEngineV2.sol";
import {IAttestationRegistry} from "./interfaces/IAttestationRegistry.sol";
import {ILoanEngine} from "./interfaces/ILoanEngine.sol";

/// @title RiskEngineV2
/// @notice Deterministic, evidence-backed scoring: attestations + protocol behavior
/// @dev Purely read-only; no ML onchain; explainable via reason codes
contract RiskEngineV2 is IRiskEngineV2 {
    bytes32 public constant MODEL_ID = keccak256("RISK_V2_2026_02_15");

    bytes32 public constant KYB_PASS = keccak256("KYB_PASS");
    bytes32 public constant DSCR_BPS = keccak256("DSCR_BPS");
    bytes32 public constant NOI_USD6 = keccak256("NOI_USD6");
    bytes32 public constant SPONSOR_TRACK = keccak256("SPONSOR_TRACK");

    bytes32 public constant REASON_KYB_PASS = keccak256("KYB_PASS");
    bytes32 public constant REASON_DSCR_STRONG = keccak256("DSCR_STRONG");
    bytes32 public constant REASON_DSCR_MID = keccak256("DSCR_MID");
    bytes32 public constant REASON_DSCR_WEAK = keccak256("DSCR_WEAK");
    bytes32 public constant REASON_NOI_PRESENT = keccak256("NOI_PRESENT");
    bytes32 public constant REASON_SPONSOR_TRACK = keccak256("SPONSOR_TRACK");
    bytes32 public constant REASON_HAS_LIQUIDATIONS = keccak256("HAS_LIQUIDATIONS");
    bytes32 public constant REASON_UTIL_HIGH = keccak256("UTIL_HIGH");
    bytes32 public constant REASON_UTIL_MID = keccak256("UTIL_MID");
    bytes32 public constant REASON_UTIL_LOW = keccak256("UTIL_LOW");
    bytes32 public constant REASON_REPAY_STALE = keccak256("REPAY_STALE");

    uint256 private constant BASE_SCORE = 520;
    uint256 private constant BPS_MAX = 10_000;
    uint256 private constant DSCR_STRONG_BPS = 13_000;
    uint256 private constant DSCR_MID_MIN_BPS = 11_500;
    uint256 private constant UTIL_HIGH_BPS = 8500;
    uint256 private constant UTIL_MID_BPS = 7000;
    uint256 private constant UTIL_LOW_BPS = 5000;
    uint256 private constant REPAY_STALE_SECS = 30 days;
    uint256 private constant CONFIDENCE_BASE = 1500;

    IAttestationRegistry public immutable attestationRegistry;
    ILoanEngine public immutable loanEngine;

    constructor(address _attestationRegistry, address _loanEngine) {
        attestationRegistry = IAttestationRegistry(_attestationRegistry);
        loanEngine = ILoanEngine(_loanEngine);
    }

    function evaluate(address subject) external view override returns (RiskOutput memory out) {
        (bytes32[] memory reasons, bytes32[] memory evidence) = _collectReasonsAndEvidence(subject);
        out.reasonCodes = reasons;
        out.evidence = evidence;

        int256 delta = 0;
        for (uint256 i = 0; i < reasons.length; i++) {
            bytes32 r = reasons[i];
            if (r == REASON_KYB_PASS) delta += 120;
            else if (r == REASON_DSCR_STRONG) delta += 160;
            else if (r == REASON_DSCR_MID) delta += 90;
            else if (r == REASON_DSCR_WEAK) delta -= 120;
            else if (r == REASON_NOI_PRESENT) delta += 60;
            else if (r == REASON_SPONSOR_TRACK) delta += 80;
            else if (r == REASON_HAS_LIQUIDATIONS) delta -= 250;
            else if (r == REASON_UTIL_HIGH) delta -= 120;
            else if (r == REASON_UTIL_MID) delta -= 60;
            else if (r == REASON_UTIL_LOW) delta += 40;
            else if (r == REASON_REPAY_STALE) delta -= 80;
        }

        out.modelId = MODEL_ID;
        out.score = uint16(_clamp(int256(BASE_SCORE) + delta, 0, 1000));
        out.tier = uint8(_scoreToTier(out.score));
        out.confidenceBps = uint16(_clamp(int256(_confidenceDeltas(subject, reasons)), 0, BPS_MAX));
    }

    function _collectReasonsAndEvidence(address subject)
        internal
        view
        returns (bytes32[] memory reasons, bytes32[] memory evidence)
    {
        bytes32[] memory r = new bytes32[](10);
        bytes32[] memory e = new bytes32[](10);
        uint256 ri = 0;
        uint256 ei = 0;

        (bool hasKyb, bytes32 idKyb) = _getValidLatest(subject, KYB_PASS);
        if (hasKyb) {
            r[ri++] = REASON_KYB_PASS;
            e[ei++] = idKyb;
        }

        (uint256 dscrBps, bytes32 idDscr) = _getDscrBps(subject);
        if (dscrBps > 0) {
            e[ei++] = idDscr;
            if (dscrBps >= DSCR_STRONG_BPS) r[ri++] = REASON_DSCR_STRONG;
            else if (dscrBps >= DSCR_MID_MIN_BPS) r[ri++] = REASON_DSCR_MID;
            else r[ri++] = REASON_DSCR_WEAK;
        }

        (bool hasNoi, bytes32 idNoi) = _getValidLatest(subject, NOI_USD6);
        if (hasNoi) {
            r[ri++] = REASON_NOI_PRESENT;
            e[ei++] = idNoi;
        }

        (bool hasSponsor, bytes32 idSponsor) = _getValidLatest(subject, SPONSOR_TRACK);
        if (hasSponsor) {
            r[ri++] = REASON_SPONSOR_TRACK;
            e[ei++] = idSponsor;
        }

        uint32 liqCount = loanEngine.liquidationCount(subject);
        if (liqCount > 0) r[ri++] = REASON_HAS_LIQUIDATIONS;

        uint256 utilBps = _getUtilizationBps(subject);
        if (utilBps >= UTIL_HIGH_BPS) r[ri++] = REASON_UTIL_HIGH;
        else if (utilBps >= UTIL_MID_BPS) r[ri++] = REASON_UTIL_MID;
        else if (utilBps > 0 && utilBps < UTIL_LOW_BPS) r[ri++] = REASON_UTIL_LOW;

        if (_isRepayStale(subject)) r[ri++] = REASON_REPAY_STALE;

        reasons = _trim(r, ri);
        evidence = _trim(e, ei);
    }

    function _getValidLatest(address subject, bytes32 aType) internal view returns (bool valid, bytes32 id) {
        id = attestationRegistry.getLatestAttestationId(subject, aType);
        if (id == bytes32(0)) return (false, bytes32(0));
        valid = attestationRegistry.isValid(id);
    }

    function _getDscrBps(address subject) internal view returns (uint256 dscrBps, bytes32 attestationId) {
        attestationId = attestationRegistry.getLatestAttestationId(subject, DSCR_BPS);
        if (attestationId == bytes32(0)) return (0, bytes32(0));
        if (!attestationRegistry.isValid(attestationId)) return (0, bytes32(0));
        (IAttestationRegistry.StoredAttestation memory att,,) = attestationRegistry.getAttestation(attestationId);
        return (uint256(att.data), attestationId);
    }

    function _getUtilizationBps(address subject) internal view returns (uint256) {
        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(subject);
        if (pos.principalAmount == 0) return 0;
        address asset = pos.collateralAsset;
        if (asset == address(0)) return 0;
        uint256 maxBorrow = loanEngine.getMaxBorrow(subject, asset);
        if (maxBorrow == 0) return 0;
        return (pos.principalAmount * BPS_MAX) / maxBorrow;
    }

    function _isRepayStale(address subject) internal view returns (bool) {
        ILoanEngine.LoanPosition memory pos = loanEngine.getPosition(subject);
        if (pos.principalAmount == 0) return false;
        uint64 lastRepay = loanEngine.lastRepayAt(subject);
        if (lastRepay == 0) return true;
        return block.timestamp > lastRepay + REPAY_STALE_SECS;
    }

    function _confidenceDeltas(address subject, bytes32[] memory reasons) internal view returns (uint256 conf) {
        conf = CONFIDENCE_BASE;
        for (uint256 i = 0; i < reasons.length; i++) {
            bytes32 r = reasons[i];
            if (r == REASON_KYB_PASS) conf += 2000;
            else if (r == REASON_DSCR_STRONG || r == REASON_DSCR_MID || r == REASON_DSCR_WEAK) conf += 2500;
            else if (r == REASON_SPONSOR_TRACK) conf += 1000;
            else if (r == REASON_NOI_PRESENT) conf += 1000;
            else if (r == REASON_HAS_LIQUIDATIONS) conf -= 1000;
        }
    }

    function _scoreToTier(uint256 score) internal pure returns (uint256) {
        if (score < 400) return 0;
        if (score < 700) return 1;
        if (score <= 850) return 2;
        return 3;
    }

    function _clamp(int256 v, int256 lo, int256 hi) internal pure returns (int256) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    }

    function _trim(bytes32[] memory arr, uint256 n) internal pure returns (bytes32[] memory) {
        bytes32[] memory out = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) out[i] = arr[i];
        return out;
    }
}
