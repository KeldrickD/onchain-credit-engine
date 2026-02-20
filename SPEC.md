# OCX Protocol Spec

Canonical definitions for integrators: subject keys, attestations, risk payloads, hashing, and nonces.

---

## 1. Subject key (subjectId / subjectKey)

- **Type:** `bytes32`
- **Semantics:** Canonical identity for a non-wallet entity (deal, SPV, pool, etc.). Same value used across SubjectRegistry, AttestationRegistry (subject attestations), RiskOracle (v2ByKey), and CreditRegistry (keyed profile).
- **Creation:** `SubjectRegistry.createSubject(subjectType, salt)` or `createSubjectWithNonce(subjectType)`.
  - `subjectId = keccak256(abi.encode(subjectType, msg.sender, salt))`.
  - `msg.sender` is the controller; delegates are set via `setDelegate(subjectId, delegate, allowed)`.
- **Authorization:** `SubjectRegistry.isAuthorized(subjectId, caller)` is true iff caller is controller or an allowed delegate.
- **Invariant:** Wallet addresses and subject keys are distinct namespaces; no overlap (address is 20 bytes, subjectId is 32 bytes).

---

## 2. Attestation types (registry conventions)

- **Wallet attestations:** `subject` is `address`; `AttestationRegistry.submitAttestation(Attestation, signature)`; nonce from `nextNonce(subject)`.
- **Subject attestations:** `subjectId` is `bytes32`; `submitSubjectAttestation(SubjectAttestation, signature)`; nonce from `nextSubjectNonce(subjectId)`.
- **attestationType:** `bytes32`. Convention: `keccak256(abi.encodePacked("LABEL"))` for string labels (e.g. `DSCR_BPS`, `NOI_USD6`, `KYB_PASS`). Registry does not enforce a fixed set; integrators can use custom types.
- **data:** `bytes32` — numeric or hash. For numeric (e.g. DSCR in bps), use `bytes32(uint256(value))`.
- **Validity:** `expiresAt == 0` means no expiry. If `expiresAt > 0`, attestation is expired when `block.timestamp >= expiresAt`. Revocation is separate (`revoke(attestationId)`).

### EIP-712 (subject attestation)

- **Type string:** `SubjectAttestation(bytes32 subjectId,bytes32 attestationType,bytes32 dataHash,bytes32 data,string uri,uint64 issuedAt,uint64 expiresAt,uint64 nonce)`
- **Domain:** name, version, chainId, verifyingContract = AttestationRegistry.
- **Hash:** struct hash from typehash + encoded fields (uri as `keccak256(bytes(uri))`). Sign `\x19\x01 ‖ domainSeparator ‖ structHash`.

---

## 3. Risk payloads

### 3.1 RiskPayload (v1, wallet)

- `user` (address), `score` (uint256), `riskTier` (uint256), `timestamp` (uint256), `nonce` (uint256).
- Nonce: `RiskOracle.nextNonce(user)`. Consumed on `verifyRiskPayload`.

### 3.2 RiskPayloadV2 (v2, wallet)

- `user` (address), `score` (uint16), `riskTier` (uint8), `confidenceBps` (uint16), `modelId` (bytes32), `reasonsHash` (bytes32), `evidenceHash` (bytes32), `timestamp` (uint64), `nonce` (uint64).
- Nonce: `RiskOracle.nextNonce(user)`.
- **reasonsHash:** `keccak256(abi.encode(reasonCodes))` where `reasonCodes` is `bytes32[]` (order matters).
- **evidenceHash:** `keccak256(abi.encode(evidence))` where `evidence` is `bytes32[]` (e.g. attestation IDs; order matters).

### 3.3 RiskPayloadV2ByKey (v2, subject)

- Same as V2 but `subjectKey` (bytes32) instead of `user` (address).
- Nonce: `RiskOracle.nextNonceKey(subjectKey)`.
- reasonsHash / evidenceHash: same encoding as V2.

### EIP-712 (V2 by key)

- **Type string:** `RiskPayloadV2ByKey(bytes32 subjectKey,uint16 score,uint8 riskTier,uint16 confidenceBps,bytes32 modelId,bytes32 reasonsHash,bytes32 evidenceHash,uint64 timestamp,uint64 nonce)`
- **Domain:** Risk Oracle domain (name, version, chainId, verifyingContract).
- Digest: `getPayloadDigestV2ByKey(payload)` on RiskOracle.

---

## 4. Hashing rules (deterministic)

| Item | Rule |
|------|------|
| **reasonsHash** | `keccak256(abi.encode(bytes32[] reasonCodes))` |
| **evidenceHash** | `keccak256(abi.encode(bytes32[] evidence))` (e.g. attestation IDs) |
| **subjectId** | `keccak256(abi.encode(subjectType, controller, salt))` |
| **Attestation struct** | EIP-712 struct hash per AttestationSignatureVerifier (uri hashed as keccak256(bytes(uri))) |

All hashes are over ABI-encoded data; no packed encoding for arrays (use `abi.encode`).

---

## 5. Nonce rules

| Context | Source | Consumed when |
|---------|--------|----------------|
| Wallet risk (v1/v2) | `RiskOracle.nextNonce(user)` | `verifyRiskPayload` / `verifyRiskPayloadV2` |
| Subject risk (v2ByKey) | `RiskOracle.nextNonceKey(subjectKey)` | `verifyRiskPayloadV2ByKey` |
| Wallet attestation | `AttestationRegistry.nextNonce(subject)` | On submit (nonce in signed payload) |
| Subject attestation | `AttestationRegistry.nextSubjectNonce(subjectId)` | On submit (nonce in signed payload) |

- Nonces are strictly increasing per subject/key. Reuse or skip causes revert.
- Consumption is on-chain at verify/submit; signer must use current nonce at signing time.

---

## 6. Validity / replay

- **Timestamp:** Oracle and signers should enforce a validity window (e.g. reject if `block.timestamp` outside `[payload.timestamp - T, payload.timestamp + T]`). Exact window is deployment-specific.
- **Nonce:** Single use; verification consumes nonce to prevent replay.
- **Attestation expiry:** `expiresAt == 0` or `block.timestamp < expiresAt` for valid; revocation is independent.

---

## 7. CreditRegistry state

- **Wallet profile:** keyed by `address`; updated via `updateCreditProfileV2(payload, signature)` (RiskOracle.verifyRiskPayloadV2).
- **Keyed profile:** keyed by `bytes32 subjectKey`; updated via `updateCreditProfileV2ByKey(payload, signature)` (RiskOracle.verifyRiskPayloadV2ByKey).
- Stored fields: score, riskTier, lastUpdated, modelId, confidenceBps, reasonsHash, evidenceHash. No separation of “wallet vs subject” beyond the key; same layout for both.

---

## 8. RiskEngineV2 (view)

- `evaluate(address)` — wallet: reads wallet attestations, returns score, tier, confidenceBps, modelId, reasonCodes[], evidence[].
- `evaluateSubject(bytes32 subjectId)` — subject: reads subject attestations, same return shape.
- Deterministic: same inputs and registry state ⇒ same output. No signing; commit to CreditRegistry is a separate step (oracle sign + verify + update).

This spec is the single source of truth for payload formats, hashes, and nonce behavior when building oracles, SDKs, and integrations.
