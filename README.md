# OCX — Onchain Credit Engine

Programmable underwriting, liquidation, and operator tooling for stablecoin lending.

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
