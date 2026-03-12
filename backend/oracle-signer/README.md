# Oracle Signer

Backend service that signs EIP-712 risk and price payloads for the OCX protocol.

## Setup

```bash
pnpm install
cp .env.example .env
```

Edit `.env`:

- `RPC_URL` - Base Sepolia RPC
- `RISK_ORACLE_ADDRESS` - RiskOracle contract
- `SIGNED_PRICE_ORACLE_ADDRESS` - SignedPriceOracle contract
- `RISK_SIGNER_PRIVATE_KEY` - Private key (no 0x prefix) for risk signing
- `PRICE_SIGNER_PRIVATE_KEY` - Same or separate key for price signing
- `ATTESTATION_REGISTRY_ADDRESS` - AttestationRegistry contract
- `ATTESTATION_SIGNER_PRIVATE_KEY` - Key for attestation signing (must have ISSUER_ROLE)
- `RISK_ENGINE_V2_ADDRESS` - RiskEngineV2 contract (for evaluate-and-sign)
- `EXPECTED_RISK_MODEL_ID` - Optional model guard (warn if mismatch)

## Endpoints

- `GET /health` - Config status
- `POST /risk/sign` - Body: `{ user, score, riskTier }` -> `{ payload, signature }`
- `POST /risk/evaluate` - Body: `{ user, kyb, dscr, noi, sponsorScore }` -> hosted signed OCX payload
- `POST /risk/evaluate-subject` - Body: `{ subjectId, kyb, dscr, noi, sponsorScore }` -> hosted signed keyed payload
- `POST /risk/evaluate-and-sign` - Body: `{ user }` -> `{ payload, signature, debug }`
- `POST /risk/evaluate-subject-and-sign` - Body: `{ subjectId }` -> `{ payload, signature, debug }`
- `POST /price/sign` - Body: `{ asset, priceUSD8 }` -> `{ payload, signature }`
- `POST /attestation/sign` - Body: `{ subject, attestationType, dataHash, data?, uri?, expiresAt? }` -> `{ payload, signature }`

## Hosted evaluator

The hosted evaluator is a fast-start lane for protocols that want signed OCX payloads before they have fully onchain attestation plumbing.

Scoring inputs:

- `kyb`
- `dscr`
- `noi`
- `sponsorScore`

Outputs include top-level `score`, `tier`, `confidenceBps`, `reasonsHash`, `evidenceHash`, plus a `payload` object compatible with `updateCreditProfileV2` or `updateCreditProfileV2ByKey`.

## Guards

- Risk: score 0-1000, tier 0-5, valid address
- Hosted eval: typed numeric inputs and valid address / subject key
- Price: price > 0, asset not zero
- Rate limit: 30 req/min per IP

## Optional

- `VERIFY_DIGEST=true` - Verify typed data digest before returning
- `CORS_ORIGIN` - Restrict CORS (default: allow all)

## Run

```bash
pnpm dev
```
