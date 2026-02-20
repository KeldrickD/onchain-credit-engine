// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskEngineV2} from "../src/RiskEngineV2.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {MockLoanEngineForRisk} from "./mocks/MockLoanEngineForRisk.sol";
import {IAttestationRegistry} from "../src/interfaces/IAttestationRegistry.sol";
import {IRiskEngineV2} from "../src/interfaces/IRiskEngineV2.sol";

contract RiskEngineV2IssuerRegistryWalletTest is Test {
    RiskEngineV2 internal engine;
    AttestationRegistry internal attestationRegistry;
    IssuerRegistry internal issuerRegistry;
    MockLoanEngineForRisk internal mockLoan;

    uint256 internal constant ISSUER_LOW_PK = 0x1001;
    uint256 internal constant ISSUER_MID_PK = 0x1002;
    uint256 internal constant ISSUER_HIGH_PK = 0x1003;
    address internal issuerLow;
    address internal issuerMid;
    address internal issuerHigh;
    address internal admin;
    address internal subject;

    bytes32 internal constant DSCR_BPS = keccak256("DSCR_BPS");

    function setUp() public {
        vm.warp(1000);
        admin = makeAddr("admin");
        subject = makeAddr("subject");
        issuerLow = vm.addr(ISSUER_LOW_PK);
        issuerMid = vm.addr(ISSUER_MID_PK);
        issuerHigh = vm.addr(ISSUER_HIGH_PK);

        attestationRegistry = new AttestationRegistry(admin);
        issuerRegistry = new IssuerRegistry(admin);
        mockLoan = new MockLoanEngineForRisk();
        engine = new RiskEngineV2(address(attestationRegistry), address(mockLoan));

        vm.startPrank(admin);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuerLow);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuerMid);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuerHigh);

        issuerRegistry.setIssuer(issuerLow, true, 3000, bytes32(0), "ipfs://low");
        issuerRegistry.setIssuer(issuerMid, true, 5000, bytes32(0), "ipfs://mid");
        issuerRegistry.setIssuer(issuerHigh, true, 10000, bytes32(0), "ipfs://high");
        issuerRegistry.setIssuerTypePermission(issuerLow, DSCR_BPS, true);
        issuerRegistry.setIssuerTypePermission(issuerMid, DSCR_BPS, true);
        issuerRegistry.setIssuerTypePermission(issuerHigh, DSCR_BPS, true);
        issuerRegistry.setMinTrustScoreBpsForType(DSCR_BPS, 7000);
        vm.stopPrank();
    }

    function _submitWalletDscr(address subj, uint256 issuerPk, bytes32 dataHash) internal returns (bytes32 id) {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: subj,
            attestationType: DSCR_BPS,
            dataHash: dataHash,
            data: bytes32(uint256(13_000)),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextNonce(subj)
        });
        bytes32 digest = attestationRegistry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        return attestationRegistry.submitAttestation(a, abi.encodePacked(r, s, v));
    }

    function test_LegacyModeUnchanged() public {
        bytes32 id = _submitWalletDscr(subject, ISSUER_LOW_PK, keccak256("legacy"));
        assertEq(engine.issuerRegistry(), address(0));

        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 680); // 520 + 160
        assertEq(out.confidenceBps, 4000); // 1500 + 2500
        assertEq(out.reasonCodes.length, 1);
        assertEq(out.reasonCodes[0], engine.REASON_DSCR_STRONG());
        assertEq(out.evidence.length, 1);
        assertEq(out.evidence[0], id);
    }

    function test_WeightedModeTrustedMatchesLegacyWith10000Trust() public {
        bytes32 id = _submitWalletDscr(subject, ISSUER_HIGH_PK, keccak256("trusted"));
        engine.setIssuerRegistry(address(issuerRegistry));

        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 680);
        assertEq(out.confidenceBps, 4000);
        assertEq(out.reasonCodes[0], engine.REASON_DSCR_STRONG());
        assertEq(out.evidence[0], id);
    }

    function test_WeightedModeMidTrustHalfScoreDelta() public {
        bytes32 id = _submitWalletDscr(subject, ISSUER_MID_PK, keccak256("mid"));
        engine.setIssuerRegistry(address(issuerRegistry));

        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 600); // 520 + (160/2)
        assertEq(out.confidenceBps, 2750); // 1500 + (2500 * 0.5)
        assertEq(out.reasonCodes[0], engine.REASON_UNTRUSTED_DSCR());
        assertEq(out.evidence[0], id);
    }

    function test_WeightedModeLowTrustZeroScoreDelta() public {
        bytes32 id = _submitWalletDscr(subject, ISSUER_LOW_PK, keccak256("low"));
        engine.setIssuerRegistry(address(issuerRegistry));

        IRiskEngineV2.RiskOutput memory out = engine.evaluate(subject);
        assertEq(out.score, 520); // no DSCR score delta
        assertEq(out.confidenceBps, 2250); // 1500 + (2500 * 0.3)
        assertEq(out.reasonCodes[0], engine.REASON_UNTRUSTED_DSCR());
        assertEq(out.evidence.length, 1);
        assertEq(out.evidence[0], id);
    }
}
