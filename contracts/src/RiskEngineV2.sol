// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRiskEngineV2} from "./interfaces/IRiskEngineV2.sol";
import {IAttestationRegistry} from "./interfaces/IAttestationRegistry.sol";
import {ILoanEngine} from "./interfaces/ILoanEngine.sol";
import {IIssuerRegistry} from "./interfaces/IIssuerRegistry.sol";

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
    bytes32 public constant REASON_SUBJECT_MODE = keccak256("SUBJECT_MODE");
    bytes32 public constant REASON_UNTRUSTED_KYB = keccak256("UNTRUSTED_KYB");
    bytes32 public constant REASON_UNTRUSTED_DSCR = keccak256("UNTRUSTED_DSCR");
    bytes32 public constant REASON_UNTRUSTED_NOI = keccak256("UNTRUSTED_NOI");
    bytes32 public constant REASON_UNTRUSTED_SPONSOR = keccak256("UNTRUSTED_SPONSOR");

    uint256 private constant BASE_SCORE = 520;
    uint256 private constant BASE_SCORE_SUBJECT = 480;
    uint256 private constant BPS_MAX = 10_000;
    uint256 private constant DSCR_STRONG_BPS = 13_000;
    uint256 private constant DSCR_MID_MIN_BPS = 11_500;
    uint256 private constant UTIL_HIGH_BPS = 8500;
    uint256 private constant UTIL_MID_BPS = 7000;
    uint256 private constant UTIL_LOW_BPS = 5000;
    uint256 private constant REPAY_STALE_SECS = 30 days;
    uint256 private constant CONFIDENCE_BASE = 1500;
    uint256 private constant CONFIDENCE_SUBJECT_MISSING_DSCR = 50;
    uint16 private constant LEGACY_TRUST_BPS = 10_000;
    uint16 private constant MID_TRUST_BPS = 4_000;

    IAttestationRegistry public immutable attestationRegistry;
    ILoanEngine public immutable loanEngine;
    address public issuerRegistry;
    address public immutable admin;

    event IssuerRegistrySet(address indexed oldRegistry, address indexed newRegistry);

    error RiskEngineV2_NotAdmin();

    constructor(address _attestationRegistry, address _loanEngine) {
        attestationRegistry = IAttestationRegistry(_attestationRegistry);
        loanEngine = ILoanEngine(_loanEngine);
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert RiskEngineV2_NotAdmin();
        _;
    }

    function setIssuerRegistry(address newRegistry) external onlyAdmin {
        emit IssuerRegistrySet(issuerRegistry, newRegistry);
        issuerRegistry = newRegistry;
    }

    function evaluate(address subject) external view override returns (RiskOutput memory out) {
        (bytes32[] memory reasons, bytes32[] memory evidence, int256 scoreDelta, uint256 conf) = _collectReasonsAndEvidence(
            subject
        );
        out.reasonCodes = reasons;
        out.evidence = evidence;

        out.modelId = MODEL_ID;
        out.score = uint16(uint256(_clamp(int256(BASE_SCORE) + scoreDelta, 0, 1000)));
        out.tier = uint8(_scoreToTier(out.score));
        out.confidenceBps = uint16(uint256(_clamp(int256(conf), 0, int256(BPS_MAX))));
    }

    function evaluateSubject(bytes32 subjectId) external view override returns (RiskOutput memory out) {
        (bytes32[] memory reasons, bytes32[] memory evidence, int256 scoreDelta, uint256 conf) =
            _collectReasonsAndEvidenceSubject(subjectId);
        out.reasonCodes = reasons;
        out.evidence = evidence;

        out.modelId = MODEL_ID;
        out.score = uint16(uint256(_clamp(int256(BASE_SCORE_SUBJECT) + scoreDelta, 0, 1000)));
        out.tier = uint8(_scoreToTier(out.score));
        out.confidenceBps = uint16(uint256(_clamp(int256(conf), 0, int256(BPS_MAX))));
    }

    function _collectReasonsAndEvidenceSubject(bytes32 subjectId)
        internal
        view
        returns (bytes32[] memory reasons, bytes32[] memory evidence, int256 scoreDelta, uint256 conf)
    {
        bytes32[] memory r = new bytes32[](8);
        bytes32[] memory e = new bytes32[](8);
        uint256 ri = 0;
        uint256 ei = 0;
        conf = CONFIDENCE_BASE;
        bool hasDscr = false;

        r[ri++] = REASON_SUBJECT_MODE;

        (bool hasKyb, bytes32 idKyb) = _getValidLatestSubject(subjectId, KYB_PASS);
        if (hasKyb) {
            (uint16 trustBps, bool trusted) = _trustSubject(idKyb, KYB_PASS);
            scoreDelta += _weightedDelta(150, trustBps, trusted);
            conf += _weightedConfidence(2000, trustBps);
            r[ri++] = trusted ? REASON_KYB_PASS : REASON_UNTRUSTED_KYB;
            e[ei++] = idKyb;
        }

        (uint256 dscrBps, bytes32 idDscr) = _getDscrBpsSubject(subjectId);
        if (dscrBps > 0) {
            hasDscr = true;
            (uint16 trustBps, bool trusted) = _trustSubject(idDscr, DSCR_BPS);
            int256 dscrDelta;
            e[ei++] = idDscr;
            if (dscrBps >= DSCR_STRONG_BPS) {
                dscrDelta = 160;
                r[ri++] = trusted ? REASON_DSCR_STRONG : REASON_UNTRUSTED_DSCR;
            } else if (dscrBps >= DSCR_MID_MIN_BPS) {
                dscrDelta = 90;
                r[ri++] = trusted ? REASON_DSCR_MID : REASON_UNTRUSTED_DSCR;
            } else {
                dscrDelta = -120;
                r[ri++] = trusted ? REASON_DSCR_WEAK : REASON_UNTRUSTED_DSCR;
            }
            scoreDelta += _weightedDelta(dscrDelta, trustBps, trusted);
            conf += _weightedConfidence(2500, trustBps);
        }

        (bool hasNoi, bytes32 idNoi, uint256 noiData) = _getValidLatestSubjectNoi(subjectId);
        if (hasNoi && noiData != 0) {
            (uint16 trustBps, bool trusted) = _trustSubject(idNoi, NOI_USD6);
            scoreDelta += _weightedDelta(80, trustBps, trusted);
            conf += _weightedConfidence(1000, trustBps);
            r[ri++] = trusted ? REASON_NOI_PRESENT : REASON_UNTRUSTED_NOI;
            e[ei++] = idNoi;
        }

        (bool hasSponsor, bytes32 idSponsor) = _getValidLatestSubject(subjectId, SPONSOR_TRACK);
        if (hasSponsor) {
            (uint16 trustBps, bool trusted) = _trustSubject(idSponsor, SPONSOR_TRACK);
            scoreDelta += _weightedDelta(100, trustBps, trusted);
            conf += _weightedConfidence(1000, trustBps);
            r[ri++] = trusted ? REASON_SPONSOR_TRACK : REASON_UNTRUSTED_SPONSOR;
            e[ei++] = idSponsor;
        }

        if (!hasDscr) conf -= CONFIDENCE_SUBJECT_MISSING_DSCR;
        reasons = _trim(r, ri);
        evidence = _trim(e, ei);
    }

    function _getValidLatestSubject(bytes32 subjectId, bytes32 aType) internal view returns (bool valid, bytes32 id) {
        id = attestationRegistry.getLatestSubjectAttestationId(subjectId, aType);
        if (id == bytes32(0)) return (false, bytes32(0));
        valid = attestationRegistry.isValid(id);
    }

    function _getDscrBpsSubject(bytes32 subjectId) internal view returns (uint256 dscrBps, bytes32 attestationId) {
        attestationId = attestationRegistry.getLatestSubjectAttestationId(subjectId, DSCR_BPS);
        if (attestationId == bytes32(0)) return (0, bytes32(0));
        if (!attestationRegistry.isValid(attestationId)) return (0, bytes32(0));
        (IAttestationRegistry.StoredSubjectAttestation memory att,,) =
            attestationRegistry.getSubjectAttestation(attestationId);
        return (uint256(att.data), attestationId);
    }

    function _getValidLatestSubjectNoi(bytes32 subjectId)
        internal
        view
        returns (bool valid, bytes32 id, uint256 data)
    {
        id = attestationRegistry.getLatestSubjectAttestationId(subjectId, NOI_USD6);
        if (id == bytes32(0)) return (false, bytes32(0), 0);
        valid = attestationRegistry.isValid(id);
        if (!valid) return (false, id, 0);
        (IAttestationRegistry.StoredSubjectAttestation memory att,,) =
            attestationRegistry.getSubjectAttestation(id);
        data = uint256(att.data);
    }

    function _confidenceDeltasSubject(bytes32 subjectId, bytes32[] memory reasons) internal view returns (uint256 conf) {
        conf = CONFIDENCE_BASE;
        bool hasDscr = false;
        for (uint256 i = 0; i < reasons.length; i++) {
            bytes32 r = reasons[i];
            if (r == REASON_KYB_PASS) conf += 2000;
            else if (r == REASON_DSCR_STRONG || r == REASON_DSCR_MID || r == REASON_DSCR_WEAK) {
                conf += 2500;
                hasDscr = true;
            } else if (r == REASON_SPONSOR_TRACK) conf += 1000;
            else if (r == REASON_NOI_PRESENT) conf += 1000;
        }
        if (!hasDscr) conf -= CONFIDENCE_SUBJECT_MISSING_DSCR;
    }

    function _collectReasonsAndEvidence(address subject)
        internal
        view
        returns (bytes32[] memory reasons, bytes32[] memory evidence, int256 scoreDelta, uint256 conf)
    {
        bytes32[] memory r = new bytes32[](12);
        bytes32[] memory e = new bytes32[](12);
        uint256 ri = 0;
        uint256 ei = 0;
        conf = CONFIDENCE_BASE;

        (bool hasKyb, bytes32 idKyb) = _getValidLatest(subject, KYB_PASS);
        if (hasKyb) {
            (uint16 trustBps, bool trusted) = _trustWallet(idKyb, KYB_PASS);
            scoreDelta += _weightedDelta(120, trustBps, trusted);
            conf += _weightedConfidence(2000, trustBps);
            r[ri++] = trusted ? REASON_KYB_PASS : REASON_UNTRUSTED_KYB;
            e[ei++] = idKyb;
        }

        (uint256 dscrBps, bytes32 idDscr) = _getDscrBps(subject);
        if (dscrBps > 0) {
            (uint16 trustBps, bool trusted) = _trustWallet(idDscr, DSCR_BPS);
            int256 dscrDelta;
            e[ei++] = idDscr;
            if (dscrBps >= DSCR_STRONG_BPS) {
                dscrDelta = 160;
                r[ri++] = trusted ? REASON_DSCR_STRONG : REASON_UNTRUSTED_DSCR;
            } else if (dscrBps >= DSCR_MID_MIN_BPS) {
                dscrDelta = 90;
                r[ri++] = trusted ? REASON_DSCR_MID : REASON_UNTRUSTED_DSCR;
            } else {
                dscrDelta = -120;
                r[ri++] = trusted ? REASON_DSCR_WEAK : REASON_UNTRUSTED_DSCR;
            }
            scoreDelta += _weightedDelta(dscrDelta, trustBps, trusted);
            conf += _weightedConfidence(2500, trustBps);
        }

        (bool hasNoi, bytes32 idNoi) = _getValidLatest(subject, NOI_USD6);
        if (hasNoi) {
            (uint16 trustBps, bool trusted) = _trustWallet(idNoi, NOI_USD6);
            scoreDelta += _weightedDelta(60, trustBps, trusted);
            conf += _weightedConfidence(1000, trustBps);
            r[ri++] = trusted ? REASON_NOI_PRESENT : REASON_UNTRUSTED_NOI;
            e[ei++] = idNoi;
        }

        (bool hasSponsor, bytes32 idSponsor) = _getValidLatest(subject, SPONSOR_TRACK);
        if (hasSponsor) {
            (uint16 trustBps, bool trusted) = _trustWallet(idSponsor, SPONSOR_TRACK);
            scoreDelta += _weightedDelta(80, trustBps, trusted);
            conf += _weightedConfidence(1000, trustBps);
            r[ri++] = trusted ? REASON_SPONSOR_TRACK : REASON_UNTRUSTED_SPONSOR;
            e[ei++] = idSponsor;
        }

        uint32 liqCount = loanEngine.liquidationCount(subject);
        if (liqCount > 0) {
            r[ri++] = REASON_HAS_LIQUIDATIONS;
            scoreDelta += -250;
            conf -= 1000;
        }

        uint256 utilBps = _getUtilizationBps(subject);
        if (utilBps >= UTIL_HIGH_BPS) {
            r[ri++] = REASON_UTIL_HIGH;
            scoreDelta += -120;
        } else if (utilBps >= UTIL_MID_BPS) {
            r[ri++] = REASON_UTIL_MID;
            scoreDelta += -60;
        } else if (utilBps > 0 && utilBps < UTIL_LOW_BPS) {
            r[ri++] = REASON_UTIL_LOW;
            scoreDelta += 40;
        }

        if (_isRepayStale(subject)) {
            r[ri++] = REASON_REPAY_STALE;
            scoreDelta += -80;
        }

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

    function _weightedConfidence(uint256 baseDelta, uint16 trustBps) internal pure returns (uint256) {
        return (baseDelta * trustBps) / LEGACY_TRUST_BPS;
    }

    function _weightedDelta(int256 fullDelta, uint16 trustBps, bool trusted) internal pure returns (int256) {
        if (trusted) return fullDelta;
        if (trustBps >= MID_TRUST_BPS) return fullDelta / 2;
        return 0;
    }

    function _trustWallet(bytes32 attestationId, bytes32 attestationType) internal view returns (uint16 trustBps, bool trusted) {
        if (issuerRegistry == address(0)) return (LEGACY_TRUST_BPS, true);
        (IAttestationRegistry.StoredAttestation memory att,,) = attestationRegistry.getAttestation(attestationId);
        if (att.issuer == address(0)) return (0, false);
        IIssuerRegistry reg = IIssuerRegistry(issuerRegistry);
        trustBps = reg.trustScoreBps(att.issuer);
        trusted = reg.isTrustedForType(att.issuer, attestationType);
    }

    function _trustSubject(bytes32 attestationId, bytes32 attestationType)
        internal
        view
        returns (uint16 trustBps, bool trusted)
    {
        if (issuerRegistry == address(0)) return (LEGACY_TRUST_BPS, true);
        (IAttestationRegistry.StoredSubjectAttestation memory att,,) = attestationRegistry.getSubjectAttestation(attestationId);
        if (att.issuer == address(0)) return (0, false);
        IIssuerRegistry reg = IIssuerRegistry(issuerRegistry);
        trustBps = reg.trustScoreBps(att.issuer);
        trusted = reg.isTrustedForType(att.issuer, attestationType);
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
