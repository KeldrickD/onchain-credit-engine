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

## Quick Integration (15 lines)

Read profile data directly from `CreditRegistry`.
Compare score/tier/confidence with your thresholds.
Gate the user flow with `PASS`/`BLOCK`.

### Subject-key lane (recommended for protocol integrations)

```ts
import { createPublicClient, http } from "viem"
import { mainnet } from "viem/chains"
import { creditRegistryAbi } from "./dist" // or correct export

const CREDIT_REGISTRY = "0x..." as `0x${string}`
const subjectKey = "0x..." as `0x${string}`

const client = createPublicClient({
  chain: mainnet,
  transport: http()
})

const profile = await client.readContract({
  address: CREDIT_REGISTRY,
  abi: creditRegistryAbi,
  functionName: "getProfile",
  args: [subjectKey]
})

const PASS =
  profile.score >= 650 &&
  profile.riskTier <= 2 &&
  profile.confidenceBps >= 6000

console.log(PASS ? "PASS" : "BLOCK")
```

### Wallet lane (EOA-based integrations)

```ts
const wallet = "0x..." as `0x${string}`

const profile = await client.readContract({
  address: CREDIT_REGISTRY,
  abi: creditRegistryAbi,
  functionName: "getCreditProfile",
  args: [wallet]
})

const PASS =
  profile.score >= 650 &&
  profile.riskTier <= 2

console.log(PASS ? "PASS" : "BLOCK")
```

## Protocol

- [SPEC.md](../../SPEC.md) — subjectKey, attestations, payload formats, hashing, nonces
- [CORE_CONTRACTS.md](../../CORE_CONTRACTS.md) — what is protocol vs examples
