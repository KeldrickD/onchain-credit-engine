# OCX Interest Model

Tier-based index accrual for scalable, audit-friendly debt accounting.

## Overview

Debt accrues per risk tier without per-user index complexity. Each tier has a global `borrowIndexRay` that compounds over time. User debt is stored as `scaledDebtRay`; actual debt = `scaledDebtRay * borrowIndexRay[tier] / RAY`.

## Tier Mapping

| Tier | Score Band | LTV   | Rate (bps) | APY  |
|------|------------|-------|------------|------|
| 0    | 0–399      | 50%   | 1500       | 15%  |
| 1    | 400–699    | 65%   | 1000       | 10%  |
| 2    | 700–850    | 75%   | 700        | 7%   |
| 3    | 851–1000   | 85%   | 500        | 5%   |

## State

- `borrowIndexRay[tier]` — compounded index (1e27 = 1x)
- `lastAccrualTimestamp[tier]` — last accrual time
- `scaledDebtRay[user]` — user’s share of tier debt
- `userTier[user]` — tier at origination (fixed for loan life)

## Accrual

On any state-changing call that touches debt:

```
elapsed = block.timestamp - lastAccrualTimestamp[tier]
multiplierRay = RAY + (rateBps * RAY / 10000) * elapsed / SECONDS_PER_YEAR
borrowIndexRay[tier] *= multiplierRay / RAY
lastAccrualTimestamp[tier] = block.timestamp
```

## Open Loan

1. Accrue tier
2. `scaledDebtRay = principal * RAY / borrowIndexRay[tier]`
3. Store `scaledDebtRay`, `userTier`

## Repay

1. Accrue tier
2. `currentDebt = scaledDebtRay * borrowIndexRay[tier] / RAY`
3. Require `amount <= currentDebt`
4. `scaledDebtRay -= amount * RAY / borrowIndexRay[tier]`

## View (getPosition)

`principalAmount` is computed as:

- `principalAmount = scaledDebtRay * _getBorrowIndexRayView(tier) / RAY`

`_getBorrowIndexRayView` applies accrual in view (no state change).

## Constants

- `RAY = 1e27`
- `SECONDS_PER_YEAR = 365.25 days`
- `BPS = 10_000`

## Rationale

- **Tier-based indices** — Differentiated pricing without per-user indices
- **Scaled debt** — Avoids looping over users; Aave-style pattern
- **Locked tier** — User’s rate fixed at origination; index still compounds globally for that tier
