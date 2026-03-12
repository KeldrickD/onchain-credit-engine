# ocx-sdk

TypeScript SDK for the **OCX** protocol: composable, attestable credit state machine for onchain identities.
Use it against any OCX-compatible registry deployment.

- **Types** — RiskPayloadV2, RiskPayloadV2ByKey, SubjectAttestationPayload, EIP712Domain
- **Hashing** — `hashReasons(reasonCodes)`, `hashEvidence(evidence)` (per [SPEC.md](../../SPEC.md))
- **Payloads** — `buildRiskPayloadV2(params)`, `buildRiskPayloadV2ByKey(params)` with correct reasonsHash/evidenceHash
- **Signing** — `riskOracleDomain()`, `riskPayloadV2TypedData()`, `riskPayloadV2ByKeyTypedData()` for viem `signTypedData` / `verifyTypedData`

## Install

```bash
pnpm add ocx-sdk viem
# or from repo
pnpm add ./packages/ocx-sdk viem
```

## Quick Integration

Read profile data from an OCX registry you choose.
Compare score/tier/confidence with your thresholds.
Gate the user flow with `PASS`/`BLOCK`.

### Subject-key lane (recommended for protocol integrations)

```ts
import { createPublicClient, http } from "viem"
import { mainnet } from "viem/chains"
import { creditRegistryAbi } from "./dist" // or correct export

const CREDIT_REGISTRY = process.env.OCX_REGISTRY as `0x${string}`
const subjectKey = process.env.OCX_SUBJECT_KEY as `0x${string}`
const MIN_SCORE = Number(process.env.OCX_MIN_SCORE ?? 650)
const MIN_CONFIDENCE_BPS = Number(process.env.OCX_MIN_CONFIDENCE_BPS ?? 6000)

const client = createPublicClient({
  chain: mainnet,
  transport: http(process.env.OCX_RPC_URL)
})

const profile = await client.readContract({
  address: CREDIT_REGISTRY,
  abi: creditRegistryAbi,
  functionName: "getProfile",
  args: [subjectKey]
})

const PASS =
  profile.score >= MIN_SCORE &&
  profile.riskTier <= 2 &&
  profile.confidenceBps >= MIN_CONFIDENCE_BPS

console.log(PASS ? "PASS" : "BLOCK")
```

### Wallet lane (EOA-based integrations)

```ts
const wallet = process.env.OCX_WALLET as `0x${string}`

const profile = await client.readContract({
  address: CREDIT_REGISTRY,
  abi: creditRegistryAbi,
  functionName: "getCreditProfile",
  args: [wallet]
})

const PASS =
  profile.score >= MIN_SCORE &&
  profile.riskTier <= 2

console.log(PASS ? "PASS" : "BLOCK")
```

Production note: treat registry address, chain, signer, and accepted `modelId` values as configuration.
OCX standardizes payloads and commit semantics, not one globally canonical deployment or score policy.

## Protocol

- [SPEC.md](../../SPEC.md) — subjectKey, attestations, payload formats, hashing, nonces
- [CORE_CONTRACTS.md](../../CORE_CONTRACTS.md) — what is protocol vs examples
