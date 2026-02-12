# OCX Collateral Risk (Phase 5.1.A2)

## Per-Asset Config (CollateralManager)

Single source of truth for risk parameters. Used by LoanEngine (max borrow, eligibility) and LiquidationManager (threshold caps).

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Asset can accrue debt if true |
| `ltvBpsCap` | uint16 | Max borrow LTV cap (overrides score curve) |
| `liquidationThresholdBpsCap` | uint16 | Max liquidation threshold cap |
| `haircutBps` | uint16 | Valuation haircut (e.g. 9000 = -10%, ≤ 10000) |
| `debtCeilingUSDC6` | uint128 | Cap on total debt against this asset (0 = no cap) |

## Constraints

- `haircutBps` ≤ 10 000
- `ltvBpsCap` ≤ `liquidationThresholdBpsCap` ≤ 10 000
- `increaseDebt` requires asset enabled and `totalDebt + amount ≤ ceiling`
- Cannot set ceiling below current `totalDebtUSDC6`

## Access Control

| Role | Permission |
|-----|------------|
| owner | `setConfig`, `setLoanEngine` |
| loanEngine | `increaseDebt`, `decreaseDebt` |

## Debt Ceiling Logic

- **On open:** `increaseDebt(asset, principalUSDC6)`
- **On repay:** `decreaseDebt(asset, repaidUSDC6)`
- **On liquidation repay:** `decreaseDebt(asset, amountRepaidUSDC6)`

Ceiling tracks outstanding debt; LoanEngine is sole caller of increase/decrease.
