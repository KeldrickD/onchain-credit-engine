# OCX — Core Contracts (Protocol)

OCX is a **composable, attestable credit state machine** for onchain identities. The protocol is the set of primitives that integrators use without adopting any specific UI or product.

## Protocol Primitives

| Contract | Role |
|----------|------|
| **SubjectRegistry** | Identity abstraction: `subjectId` (bytes32) with controller + delegates; `createSubject` / `createSubjectWithNonce`; `isAuthorized`, `controllerOf`, `subjectTypeOf`. |
| **AttestationRegistry** | Evidence layer: wallet attestations + **subject attestations** (by `subjectId`); submit + revoke; `getLatest` / `getLatestSubject`, `getSubjectAttestation`; nonce per subject and per subjectId. |
| **RiskOracle** | Signed risk payloads: v1 (wallet), v2 (wallet), **v2ByKey** (subjectKey); EIP-712; nonce + timestamp; `nextNonce` / `nextNonceKey`. |
| **CreditRegistry** | Committed credit state: wallet profiles (`getCreditProfile`) + **keyed profiles** (`getProfile(bytes32 subjectKey)`); `updateCreditProfileV2` / `updateCreditProfileV2ByKey`. |
| **RiskEngineV2** | Deterministic evaluation: `evaluate(address)` and `evaluateSubject(bytes32 subjectId)`; reason codes + evidence; reads from AttestationRegistry. |
| **SignedPriceOracle** | Signed price payloads; EIP-712; nonce per asset. |
| **PriceRouter** | Price source aggregation (signed / chainlink / fixed). |
| **CollateralManager** | Collateral accounting (deposit/withdraw, balances). |
| **LiquidationManager** | Health factor, liquidation execution. |
| **LoanEngine** | Reference lending logic: origination gated by risk tier, pricing, repay. |
| **TreasuryVault** | Vault for protocol / treasury. |

## What “core” means

- **No product assumptions** — No real-estate, no “deals,” no capital stack. Just identity, attestations, risk evaluation, and committed state.
- **Subject-key parity** — Wallet and subject (bytes32) lanes are parallel: attestations, nonces, risk payloads, and credit profiles exist for both.
- **Deterministic + signed** — RiskEngineV2 is view; RiskOracle signs offchain; CreditRegistry stores the committed result. Same inputs → same evaluation; commit is permissionless with valid signature.

## Interfaces & paths

- `contracts/src/` — Core contracts and `interfaces/` (except example-specific interfaces).
- `contracts/src/libraries/` — SignatureVerifier, AttestationSignatureVerifier, PriceSignatureVerifier.
- See [SPEC.md](./SPEC.md) for payload formats, hashing, nonce rules, and attestation conventions.

## Out of scope for “core”

- Deal packaging, deal types, capital stack suggestion, and any “Deals” UI live in **examples** or **apps**. See [EXAMPLES.md](./EXAMPLES.md).
