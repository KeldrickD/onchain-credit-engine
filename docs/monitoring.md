# OCX Protocol Monitoring

Operator layer for monitoring protocol events, detecting anomalies, and exporting incidents.

## Quick Start

```bash
pnpm monitor -- --rpc $BASE_SEPOLIA_RPC_URL --lookback 5000 --step 1000
```

## CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `--rpc <url>` | RPC URL (required) | - |
| `--lookback <blocks>` | Blocks to scan backwards from latest | 5000 |
| `--step <blocks>` | Max log range per request (avoids RPC limits) | 1000 |
| `--out-dir <path>` | Output directory for snapshots and incidents | `.` |

## Outputs

- **`monitor_snapshots/latest.json`** — Snapshot of events, counts, last seen, anomalies, and risk context
- **`incident_exports/<incidentId>.json`** — Only when anomaly rules trigger

## Configuration

Contract addresses are loaded from `backend/monitor/config.json`:

```json
{
  "baseSepolia": {
    "chainId": 84532,
    "network": "base-sepolia",
    "contracts": {
      "loanEngine": "",
      "vault": "",
      "priceOracle": "",
      "registry": "",
      "liqManager": ""
    }
  }
}
```

Addresses can be overridden via environment variables:

- `LOAN_ENGINE`
- `TREASURY_VAULT`
- `PRICE_ORACLE`
- `CREDIT_REGISTRY`
- `LIQUIDATION_MANAGER`

## Decoded Events

| Contract | Event |
|----------|-------|
| SignedPriceOracle | PriceUpdated(asset, price) |
| CreditRegistry | CreditProfileUpdated(user, score, riskTier, timestamp, nonce) |
| LoanEngine | CollateralDeposited(user, amount) |
| LoanEngine | LoanOpened(borrower, collateral, principal, ltvBps, rateBps) |
| LoanEngine | LoanRepaid(borrower, amount, remainingPrincipal) |
| LoanEngine | CollateralWithdrawn(user, amount) |
| LoanEngine | LiquidationRepay(borrower, amount, remainingPrincipal) |
| LoanEngine | CollateralSeized(borrower, to, amount) |
| LiquidationManager | Liquidated(borrower, liquidator, repayAmount, collateralSeized) |
| TreasuryVault | Deposited(user, amount) |
| TreasuryVault | Withdrawn(user, amount) |

## Anomaly Rules (v0)

| Rule | Trigger |
|------|---------|
| **Liquidation burst** | ≥5 liquidations within 50 blocks |
| **Price feed spam** | ≥10 PriceUpdated within 200 blocks |
| **Oracle staleness** | Latest price update older than 10 minutes |
| **Borrow surge** | >20 LoanOpened within 500 blocks |
| **Repay spike after liquidations** | ≥10 repays within 200 blocks after a liquidation burst |

## Risk Context

When `backend/risk-sim/reports/latest.json` exists, the snapshot includes a `riskContext` block with:

- `liqFreq` — Liquidation frequency from latest sim
- `expectedLossPct` — Expected loss %
- `mostSensitiveInputs` — Most sensitive simulation parameters

## Incident Export Shape

When any anomaly rule triggers:

```json
{
  "id": "incident-...",
  "triggeredRules": ["liquidation_burst: ..."],
  "timeWindow": { "fromBlock": 0, "toBlock": 0 },
  "topTxs": ["0x..."],
  "decodedEvents": [...],
  "configSnapshot": { "loanEngine": "...", ... },
  "riskSimSummary": { "liqFreq": 0.99, "expectedLossPct": 43.6, "mostSensitiveInputs": [...] },
  "recommendedActions": ["Check liquidationManager...", ...],
  "notes": "..."
}
```
