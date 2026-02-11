# OCX Loan Model (v0)

## State

### LoanPosition

| Field | Description |
|-------|-------------|
| `collateralAmount` | Collateral deposited at open |
| `principalAmount` | USDC borrowed |
| `openedAt` | Timestamp when loan opened |
| `ltvBps` | LTV at origination (basis points) |
| `interestRateBps` | Rate at origination (basis points) |

### Rules

- **Single loan per borrower** (MVP)
- **Collateral held in LoanEngine** (not TreasuryVault)
- **Repay**: User approves vault for USDC; `repay()` calls `vault.pullFromBorrower(user, amount)`

## Score → Terms Curve (v0)

| Score Range | LTV | Interest Rate |
|-------------|-----|---------------|
| 0–399 | 50% | 1500 bps (15%) |
| 400–699 | 65% | 1000 bps (10%) |
| 700–850 | 75% | 700 bps (7%) |
| 851–1000 | 85% | 500 bps (5%) |

## Formulas

### Max Borrow (MVP: 1:1 collateral price)

```
maxBorrow = collateralAmount * ltvBps / 10_000 / 1e12
```

(1e12 = 18 - 6 decimals, collateral to USDC)

### Withdraw Collateral (LTV constraint)

Withdraw allowed only if:

```
principal <= (remainingCollateral * ltvBps / 10_000) / 1e12
```

## Flow

1. Borrower deposits collateral → LoanEngine
2. Borrower submits signed RiskPayload + borrowAmount
3. LoanEngine: CreditRegistry.updateCreditProfile (consumes nonce)
4. LoanEngine: compute terms from score, check maxBorrow
5. LoanEngine: vault.transferToBorrower(borrower, amount)
6. Repay: vault.pullFromBorrower(borrower, amount); principal -= amount
