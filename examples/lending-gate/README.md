# Lending Gate Example

Minimal OCX consumer example showing both:

- onchain enforcement (`contracts/LendingGate.sol`)
- TypeScript integration (`script/gate.ts`)

This is an example consumer. OCX core protocol lives in `contracts/src`.

## Requirements

- Node.js + pnpm
- Foundry
- RPC endpoint

## Read-only proof (no signing keys)

```bash
cd examples/lending-gate
pnpm i

RPC_URL=... CREDIT_REGISTRY=0x... SUBJECT_KEY=0x... pnpm gate:key
RPC_URL=... CREDIT_REGISTRY=0x... WALLET=0x... pnpm gate:wallet
```

Both commands print:

- profile fields (`score`, `tier`, `confidenceBps`)
- gate thresholds
- `PASS` / `FAIL`

## Full demo (onchain-backed evaluate and sign)

Requires a running oracle-signer backend and a funded transaction key:

```bash
cd examples/lending-gate
pnpm i

ORACLE_SIGNER_URL=http://localhost:3001 \
RPC_URL=... \
CREDIT_REGISTRY=0x... \
WALLET=0x... \
PRIVATE_KEY=0x... \
pnpm commit:wallet
```

Keyed mode:

```bash
ORACLE_SIGNER_URL=http://localhost:3001 \
RPC_URL=... \
CREDIT_REGISTRY=0x... \
SUBJECT_KEY=0x... \
PRIVATE_KEY=0x... \
pnpm commit:key
```

The commit commands:

- call `/risk/evaluate-and-sign` or `/risk/evaluate-subject-and-sign`
- verify deterministic `reasonsHash` / `evidenceHash` using `ocx-sdk` hash helpers
- submit `updateCreditProfileV2` or `updateCreditProfileV2ByKey`
- re-read profile and print gate `PASS`/`FAIL`

## Hosted normalized-input lane

The same signer service now exposes a faster-start hosted evaluation path:

- `POST /risk/evaluate`
- `POST /risk/evaluate-subject`

These routes accept normalized inputs like `kyb`, `dscr`, `noi`, and `sponsorScore`, then return a signed OCX-compatible payload that can be committed through the same registry methods.

This example script still demonstrates the trust-minimized onchain-backed flow, but the hosted lane is useful when an integrating protocol wants to start before moving its attestations fully onchain.

## Gate thresholds

Optional env vars:

- `MIN_SCORE` (default `600`)
- `MAX_TIER` (default `2`)
- `USE_CONFIDENCE` (`true`/`false`, default `false`)
- `MIN_CONFIDENCE_BPS` (default `5000`)
