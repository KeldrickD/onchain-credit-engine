# OCX — Examples & Optional Apps

These are **non-protocol** layers built on top of OCX. They show how to use the core primitives; they are not required for integration.

## DealFactory (example contract)

- **Path:** `contracts/src/examples/DealFactory.sol`
- **Purpose:** Creates first-class “deal” subjects (sponsor, metadata URI, requested capital, collateral asset) by calling `SubjectRegistry.createSubjectWithNonce(dealType)` and storing deal metadata.
- **Depends on:** SubjectRegistry (core). No change to protocol invariants.
- **Tests:** `contracts/test/DealFactory.t.sol`

## Demo frontend: Deals & underwriting

- **Paths:** `frontend/src/app/deals/`, `frontend/src/components/deals/`
- **Purpose:** Demo UI for creating deals, viewing deal detail, running “Evaluate & Commit” (subject risk flow), exporting underwriting packets, and viewing a suggested capital stack.
- **Label in UI:** Under **Examples** in the nav (not “the product” — the product is the protocol).
- **Depends on:** Core contracts (SubjectRegistry, AttestationRegistry, RiskEngineV2, CreditRegistry, RiskOracle), optional DealFactory, optional backend capital-stack endpoint.

## Capital stack suggestion (example backend)

- **Path:** `backend/capital-stack/`
- **Purpose:** Deterministic suggestion of senior/mezz/pref/common from an underwriting packet (tier, DSCR, confidence, attestation flags). Pure inference; no onchain state.
- **Endpoint:** `POST /capital-stack/suggest` (mounted on oracle-signer).
- **Use case:** Example of “risk → structure” tooling; integrators can replace with their own logic.

## Using the protocol without examples

You can integrate OCX without deploying DealFactory or using the Deals UI:

1. Use **SubjectRegistry** to create and control subject IDs.
2. Use **AttestationRegistry** to submit subject attestations (DSCR, NOI, KYB, etc.).
3. Use **RiskEngineV2.evaluateSubject(subjectId)** for deterministic score/tier/confidence.
4. Use **RiskOracle** (offchain signer) to produce signed v2ByKey payloads and **CreditRegistry.updateCreditProfileV2ByKey** to commit.
5. Gate your own lending, allowlist, or pricing logic on `CreditRegistry.getProfile(subjectKey)` or wallet profile.

See [packages/ocx-sdk](./packages/ocx-sdk) for typed helpers and a minimal integration example.
