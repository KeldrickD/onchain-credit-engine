# OCX — Onchain Credit Engine

**A composable, attestable credit state machine for onchain identities.**  
Deterministic evaluation, signed commits, and reusable subject keys. No governance, no tokens—just the protocol.

## Protocol-first

- **[CORE_CONTRACTS.md](CORE_CONTRACTS.md)** — What counts as protocol (SubjectRegistry, AttestationRegistry, RiskOracle, CreditRegistry, RiskEngineV2, etc.).
- **[EXAMPLES.md](EXAMPLES.md)** — Optional apps (DealFactory, Deals demo UI, capital-stack suggestion) built on top.
- **[SPEC.md](SPEC.md)** — Canonical spec: subjectKey, attestations, payload formats, hashing, nonces.
- **[packages/ocx-sdk](packages/ocx-sdk)** — TypeScript SDK: types, `hashReasons` / `hashEvidence`, `buildRiskPayloadV2ByKey`, EIP-712 helpers; first integration example.

## Overview

OCX is an infrastructure layer for EVM-based stablecoin lending: smart contracts hold custody and enforce loan terms; offchain oracles supply signed risk and price payloads; a loan engine gates origination by score bands; a liquidation manager keeps positions solvent; and operator tooling (monitoring, stress testing) surfaces anomalies and parameter recommendations. No governance, no tokens—just the plumbing.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Contracts  │────▶│   Oracles   │────▶│   Engine    │
│ RiskOracle  │     │ EIP-712     │     │ LoanEngine  │
│ PriceOracle │     │ Risk+Price  │     │ Liquidation │
│ CreditReg   │     └─────────────┘     │ Manager     │
└─────────────┘                         └──────┬──────┘
                                                │
       ┌───────────────────────────────────────┼───────────────────────────────────────┐
       │                                       ▼                                       │
       │                              ┌─────────────┐                                   │
       │                              │    Vault    │                                   │
       │                              │ TreasuryVault│                                  │
       │                              └─────────────┘                                   │
       │                                                                                │
       │  ┌─────────────┐                                      ┌─────────────┐         │
       └─▶│   Monitor   │◀─── log scan, anomaly rules ────────▶│  RiskSim    │         │
          │ incident export                                     │ Monte Carlo │         │
          └─────────────┘                                       │ recommend   │         │
                                                                └─────────────┘         │
```

## Core Capabilities

- **EIP-712 signed risk + price oracles** — Offchain signing; nonce + timestamp replay protection
- **Score-driven loan origination** — Credit bands map to LTV and interest rate; single loan per borrower
- **Liquidation engine with close factor + bonus** — Health-factor gated; keeper-style liquidations
- **Monte Carlo stress testing + parameter recommendations** — Simulates market shocks; recommends threshold/close factor/bonus tweaks
- **Monitoring + incident export tooling** — Scans logs, detects anomalies (bursts, staleness, surges), exports runbooks

## How to Run Locally

```bash
# Clone (includes forge-std submodule)
git clone --recurse-submodules https://github.com/KeldrickD/onchain-credit-engine.git
cd onchain-credit-engine

# Install Foundry (WSL2 recommended on Windows)
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc && foundryup

# Run contracts tests
cd contracts && forge test

# Run risk simulation (Monte Carlo stress)
pnpm risk:sim

# Run monitor (requires RPC; set addresses in backend/monitor/config.json after deploy)
pnpm monitor -- --rpc $BASE_SEPOLIA_RPC_URL --lookback 5000 --step 1000

# Run frontend (Next.js + wagmi)
cd frontend && cp .env.example .env.local  # then edit .env.local with contract addresses
pnpm frontend  # or: cd frontend && pnpm dev
```

### Contract Test Runner (portable)

```bash
# Run all contract tests via helper (works with forge on PATH or ~/.foundry/bin/forge)
cd contracts
./script/test.sh

# Run the end-to-end underwriting -> commit -> pricing proof test
forge test --match-path test/E2E_RiskCommit.t.sol -vvv
```

## Threat Model

See [docs/threat-model.md](docs/threat-model.md) for:

- **Oracle trust boundary** — Semi-trusted signers; compromise impacts scoring and liquidations
- **Replay protection** — Per-user (risk) and per-asset (price) nonces; timestamp validity windows
- **Reentrancy tests** — ReentrancyGuard on LiquidatationManager, LoanEngine, TreasuryVault; malicious-collateral tests
- **Known limitations** — Centralized price source in MVP; governance/MEV out of scope

## What’s Intentionally Not Built

- **No governance** — Parameters set by owner; no DAO or voting
- **No yield farming** — No LP incentives or reward tokens
- **No token incentives** — No protocol token or staking
- **No decentralization theater** — Oracles are explicitly semi-trusted; documented and testable

## License

MIT
