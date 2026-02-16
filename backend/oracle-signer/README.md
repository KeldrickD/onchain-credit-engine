# Oracle Signer

Backend service that signs EIP-712 risk and price payloads for the OCX protocol.

## Setup

```bash
pnpm install
cp .env.example .env
```

Edit `.env`:

- `RPC_URL` — Base Sepolia RPC
- `RISK_ORACLE_ADDRESS` — RiskOracle contract
- `SIGNED_PRICE_ORACLE_ADDRESS` — SignedPriceOracle contract
- `RISK_SIGNER_PRIVATE_KEY` — Private key (no 0x prefix) for risk signing
- `PRICE_SIGNER_PRIVATE_KEY` — Same or separate key for price signing
- `ATTESTATION_REGISTRY_ADDRESS` — AttestationRegistry contract
- `ATTESTATION_SIGNER_PRIVATE_KEY` — Key for attestation signing (must have ISSUER_ROLE)
- `RISK_ENGINE_V2_ADDRESS` — RiskEngineV2 contract (for evaluate-and-sign)
- `EXPECTED_RISK_MODEL_ID` — Optional model guard (warn if mismatch)

## Endpoints

- `GET /health` — Config status
- `POST /risk/sign` — Body: `{ user, score, riskTier }` → `{ payload, signature }`
- `POST /risk/evaluate-and-sign` — Body: `{ user }` → `{ payload, signature, debug }`
- `POST /price/sign` — Body: `{ asset, priceUSD8 }` → `{ payload, signature }`
- `POST /attestation/sign` — Body: `{ subject, attestationType, dataHash, data?, uri?, expiresAt? }` → `{ payload, signature }`

## Guards

- Risk: score 0–1000, tier 0–5, valid address
- Price: price > 0, asset not zero
- Rate limit: 30 req/min per IP

## Optional

- `VERIFY_DIGEST=true` — Verify typed data digest before returning (elite safety)
- `CORS_ORIGIN` — Restrict CORS (default: allow all)

## Run

```bash
pnpm dev
```
