# ocx-sdk

TypeScript SDK for the **OCX** protocol: composable, attestable credit state machine for onchain identities.

- **Types** — RiskPayloadV2, RiskPayloadV2ByKey, SubjectAttestationPayload, EIP712Domain
- **Hashing** — `hashReasons(reasonCodes)`, `hashEvidence(evidence)` (per [SPEC.md](../../SPEC.md))
- **Payloads** — `buildRiskPayloadV2ByKey(params)` with correct reasonsHash/evidenceHash
- **Signing** — `riskOracleDomain()`, `riskPayloadV2ByKeyTypedData()` for viem `signTypedData` / `verifyTypedData`

## Install

```bash
pnpm add ocx-sdk viem
# or from repo
pnpm add ./packages/ocx-sdk viem
```

## Use

```ts
import { buildRiskPayloadV2ByKey, hashReasons, hashEvidence } from "ocx-sdk";
import { riskPayloadV2ByKeyTypedData, riskOracleDomain } from "ocx-sdk";

const payload = buildRiskPayloadV2ByKey({
  subjectKey: "0x...",
  score: 720,
  riskTier: 2,
  confidenceBps: 7500,
  modelId: "0x...",
  reasonCodes: ["0x..."],
  evidence: ["0x..."],
  timestamp: BigInt(Math.floor(Date.now() / 1000)),
  nonce: 1n,
});

const typedData = riskPayloadV2ByKeyTypedData(
  riskOracleDomain(chainId, riskOracleAddress),
  payload
);
// await walletClient.signTypedData(typedData);
```

## Example

See [examples/integrate-lending-gate.ts](./examples/integrate-lending-gate.ts) for a minimal “gate lending by CreditRegistry.getProfile(subjectKey)” flow.

## Protocol

- [SPEC.md](../../SPEC.md) — subjectKey, attestations, payload formats, hashing, nonces
- [CORE_CONTRACTS.md](../../CORE_CONTRACTS.md) — what is protocol vs examples
