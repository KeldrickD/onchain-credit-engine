// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {RiskOracle} from "../../src/RiskOracle.sol";
import {SignedPriceOracle} from "../../src/SignedPriceOracle.sol";
import {AttestationRegistry} from "../../src/AttestationRegistry.sol";
import {CreditRegistry} from "../../src/CreditRegistry.sol";

import {IRiskOracle} from "../../src/interfaces/IRiskOracle.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";
import {IAttestationRegistry} from "../../src/interfaces/IAttestationRegistry.sol";

contract NonceActions {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant RISK_ORACLE_PK = 0xA11CE;
    uint256 internal constant PRICE_ORACLE_PK = 0xB0B;
    uint256 internal constant ATTESTATION_ISSUER_PK = 0xCAFE;

    address internal constant USER = address(0xBEEF);
    address internal constant ASSET = address(0xCAFE);
    bytes32 internal constant SUBJECT_ID = keccak256("INVARIANT_SUBJECT");

    RiskOracle internal riskOracle;
    SignedPriceOracle internal priceOracle;
    AttestationRegistry internal attestationRegistry;
    CreditRegistry internal creditRegistry;

    constructor(
        RiskOracle riskOracle_,
        SignedPriceOracle priceOracle_,
        AttestationRegistry attestationRegistry_,
        CreditRegistry creditRegistry_
    ) {
        riskOracle = riskOracle_;
        priceOracle = priceOracle_;
        attestationRegistry = attestationRegistry_;
        creditRegistry = creditRegistry_;
    }

    function actCommitWalletRisk(uint16 scoreSeed) external {
        uint16 score = uint16(uint256(scoreSeed) % 1001);
        IRiskOracle.RiskPayloadV2 memory p = IRiskOracle.RiskPayloadV2({
            user: USER,
            score: score,
            riskTier: uint8(score % 4),
            confidenceBps: 5000,
            modelId: keccak256("INVARIANT_MODEL"),
            reasonsHash: keccak256("reasons"),
            evidenceHash: keccak256("evidence"),
            timestamp: uint64(block.timestamp),
            nonce: uint64(riskOracle.nextNonce(USER))
        });

        bytes32 digest = riskOracle.getPayloadDigestV2(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(RISK_ORACLE_PK, digest);
        creditRegistry.updateCreditProfileV2(p, abi.encodePacked(r, s, v));
    }

    function actSubmitPrice(uint256 priceSeed) external {
        uint256 price = 1e8 + (priceSeed % (5_000e8));
        IPriceOracle.PricePayload memory p = IPriceOracle.PricePayload({
            asset: ASSET,
            price: price,
            timestamp: block.timestamp,
            nonce: priceOracle.nextNonce(ASSET)
        });

        bytes32 digest = priceOracle.getPricePayloadDigest(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRICE_ORACLE_PK, digest);
        priceOracle.verifyPricePayload(p, abi.encodePacked(r, s, v));
    }

    function actSubmitWalletAttestation(bytes32 dataSeed) external {
        IAttestationRegistry.Attestation memory a = IAttestationRegistry.Attestation({
            subject: USER,
            attestationType: keccak256("KYB_PASS"),
            dataHash: keccak256(abi.encode(dataSeed)),
            data: bytes32(0),
            uri: "ipfs://wallet-att",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextNonce(USER)
        });
        bytes32 digest = attestationRegistry.getAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTATION_ISSUER_PK, digest);
        attestationRegistry.submitAttestation(a, abi.encodePacked(r, s, v));
    }

    function actSubmitSubjectAttestation(bytes32 dataSeed) external {
        IAttestationRegistry.SubjectAttestation memory a = IAttestationRegistry.SubjectAttestation({
            subjectId: SUBJECT_ID,
            attestationType: keccak256("DSCR_BPS"),
            dataHash: keccak256(abi.encode(dataSeed)),
            data: bytes32(uint256(13_000)),
            uri: "ipfs://subject-att",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: attestationRegistry.nextSubjectNonce(SUBJECT_ID)
        });
        bytes32 digest = attestationRegistry.getSubjectAttestationDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTATION_ISSUER_PK, digest);
        attestationRegistry.submitSubjectAttestation(a, abi.encodePacked(r, s, v));
    }
}

contract InvariantNonces is Test {
    uint256 internal constant RISK_ORACLE_PK = 0xA11CE;
    uint256 internal constant PRICE_ORACLE_PK = 0xB0B;
    uint256 internal constant ATTESTATION_ISSUER_PK = 0xCAFE;

    address internal constant USER = address(0xBEEF);
    address internal constant ASSET = address(0xCAFE);
    bytes32 internal constant SUBJECT_ID = keccak256("INVARIANT_SUBJECT");

    RiskOracle internal riskOracle;
    SignedPriceOracle internal priceOracle;
    AttestationRegistry internal attestationRegistry;
    CreditRegistry internal creditRegistry;
    NonceActions internal actions;

    uint256 internal lastRiskNonce;
    uint256 internal lastPriceNonce;
    uint256 internal lastWalletAttestationNonce;
    uint256 internal lastSubjectAttestationNonce;

    function setUp() external {
        address riskSigner = vm.addr(RISK_ORACLE_PK);
        address priceSigner = vm.addr(PRICE_ORACLE_PK);
        address issuer = vm.addr(ATTESTATION_ISSUER_PK);
        address admin = makeAddr("admin");

        riskOracle = new RiskOracle(riskSigner);
        priceOracle = new SignedPriceOracle(priceSigner);
        attestationRegistry = new AttestationRegistry(admin);
        creditRegistry = new CreditRegistry(address(riskOracle));

        vm.startPrank(admin);
        attestationRegistry.grantRole(attestationRegistry.ISSUER_ROLE(), issuer);
        vm.stopPrank();

        actions = new NonceActions(riskOracle, priceOracle, attestationRegistry, creditRegistry);
        targetContract(address(actions));

        lastRiskNonce = riskOracle.nextNonce(USER);
        lastPriceNonce = priceOracle.nextNonce(ASSET);
        lastWalletAttestationNonce = attestationRegistry.nextNonce(USER);
        lastSubjectAttestationNonce = attestationRegistry.nextSubjectNonce(SUBJECT_ID);
    }

    function invariant_NoncesNeverDecrease() external {
        uint256 riskNow = riskOracle.nextNonce(USER);
        uint256 priceNow = priceOracle.nextNonce(ASSET);
        uint256 walletAttNow = attestationRegistry.nextNonce(USER);
        uint256 subjectAttNow = attestationRegistry.nextSubjectNonce(SUBJECT_ID);

        assertGe(riskNow, lastRiskNonce);
        assertGe(priceNow, lastPriceNonce);
        assertGe(walletAttNow, lastWalletAttestationNonce);
        assertGe(subjectAttNow, lastSubjectAttestationNonce);

        lastRiskNonce = riskNow;
        lastPriceNonce = priceNow;
        lastWalletAttestationNonce = walletAttNow;
        lastSubjectAttestationNonce = subjectAttNow;
    }
}
