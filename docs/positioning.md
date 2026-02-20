# OCX Positioning Thesis

## What OCX is

OCX is an onchain credit state machine that separates credit state from lending execution. It defines how credit is stored and verified, not how capital is deployed.

Identity, attestation, and scoring are separated into reusable primitives. Credit profiles are deterministic, attestation-backed, and keyed to both wallets and abstract subject keys (deals, SPVs, pools, entities). Profiles are updated through EIP-712 signed oracle payloads with nonce-based replay protection, and read through a pure evaluation engine that produces explainable scores, tiers, confidence levels, and reason codes.

The protocol has two identity lanes:

- **Wallet lane** — keyed by `address`, for EOA/contract-level credit state.
- **Subject-key lane** — keyed by `bytes32`, for non-wallet entities (deals, funds, counterparties).

Both lanes share the same profile shape, the same oracle verification path, and the same CI-enforced behavioral spec.

OCX rejects binary issuer whitelists. Instead, issuer credibility is expressed as a continuous trust score (`trustScoreBps`), and attestation factors are scaled accordingly. Untrusted issuers still contribute evidence; they just contribute less signal.

All protocol behavior is anchored to an onchain `SPEC_VERSION` constant, verified by golden vector tests, and hardened by invariant tests under deterministic CI.

## What OCX is not

- **Not a lending protocol.** OCX does not originate loans, hold collateral, or liquidate positions. It produces credit state. Lending protocols consume it.
- **Not an identity system.** Subject keys are opaque `bytes32` values. OCX does not resolve, verify, or manage identity. It stores attestation-backed evaluations keyed by identity.
- **Not a governance system.** Parameters are owner-set. There is no DAO, no voting, no token.
- **Not an oracle network.** It verifies signatures. It does not produce consensus. OCX verifies signed payloads from a designated signer. It does not aggregate feeds, run consensus, or decentralize signing. That is a future layer, not a current claim.

## Who should integrate

- **Lending protocols** that need a portable credit signal to gate origination, set terms, or adjust risk parameters per borrower or deal.
- **Underwriting platforms** that produce attestations (KYB, DSCR, NOI, sponsor track) and want those attestations to flow into a composable scoring layer.
- **RWA tokenization platforms** that need subject-key-level risk profiles attached to deals or SPVs, not just wallet addresses.
- **DeFi-native venues** — margin platforms, perp protocols, structured credit vaults — that need onchain credit gating without building custom risk infrastructure.
- **Protocol risk committees** that want deterministic, auditable credit evaluation with explainable reason codes and trust-weighted confidence.

## Why now

Onchain lending is growing, but credit state is fragmented. Most protocols implement isolated credit checks or offchain heuristics that are not portable across venues. The result: incompatible credit signals, duplicated infrastructure, and no composability between lending venues.

OCX exists because credit state should be a shared primitive, not a per-protocol silo.

The timing is specific:

- EIP-712 signing is mature and well-tooled.
- Subject-key abstraction (keying risk to deals, not just wallets) is increasingly demanded by RWA protocols but not standardized.
- Trust-weighted attestation (where issuer credibility scales signal strength) is the missing layer between "trusted issuer list" and "fully decentralized oracle" — and most protocols need the middle ground now.

## 3 canonical use cases

**1. Lending gate**
A lending protocol reads `CreditRegistry.getCreditProfile(borrower)`. If `score >= 650` and `riskTier <= 2`, the borrower can open a position. If not, the transaction reverts. No custom risk logic required. 15 lines of integration.

**2. Deal-level underwriting**
An RWA originator creates a subject key for a deal via `SubjectRegistry`. Attestations (DSCR, NOI, KYB, sponsor track) are submitted by authorized issuers. `RiskEngineV2.evaluateSubject(subjectKey)` produces a deterministic score. The oracle signs and commits it to `CreditRegistry` via the keyed lane. Downstream protocols read the profile by key.

**3. Issuer trust weighting**
Multiple attestation issuers provide KYB or DSCR signals for the same subject. `IssuerRegistry` assigns each issuer a `trustScoreBps`. RiskEngineV2 weights their contributions: trusted issuers get full score delta; partially trusted issuers get half; untrusted issuers get zero delta but their evidence is still recorded. This allows attestation quality to be expressed quantitatively without requiring governance votes to add or remove issuers.

## v0.2 decision framework

v0.2 should commit to exactly one of these directions. Each is viable; none is wrong. The choice depends on where OCX wants to create lock-in.

| Direction | Core bet | v0.2 scope | Lock-in mechanism |
|-----------|----------|------------|-------------------|
| **Credit Primitive** | OCX becomes "ERC-20 for credit state" — the standard profile format that lending protocols read. | Formalize `ICreditRegistry` as an EIP-style interface. Add multi-registry support. Publish integration adapters for 2-3 existing lending protocols. | Network effects: more protocols reading OCX profiles = more issuers writing to them. |
| **Trust-Weighted Attestation Layer** | OCX becomes the canonical layer for issuer competition and weighted trust signals. | Expand `IssuerRegistry` with staking, slashing, or reputation decay. Add cross-attestation-type trust (issuer trusted for KYB may not be trusted for DSCR). Publish issuer onboarding flow. | Issuer ecosystem: issuers invest in building trust score, creating switching costs. |
| **Underwriting Substrate** | OCX becomes the default risk infrastructure that lending protocols deploy on top of. | Harden `LoanEngine` + `LiquidationManager`. Add configurable term sheets. Build a "deploy your lending protocol on OCX" template. | Vertical integration: protocols built on OCX are deeply coupled to its risk stack. |

The honest constraint: pursuing all three dilutes each. Pick the one where OCX has the strongest existing advantage and the clearest path to adoption.

Current signal suggests **Credit Primitive** is the least assumption-heavy path (interface-only integration, no new trust assumptions) and the broadest surface area. But if the RWA pipeline is real, **Underwriting Substrate** may have higher lock-in per integration.

The decision should be made based on where the first 3 real integrations come from.
