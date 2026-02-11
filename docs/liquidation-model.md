# OCX Liquidation Model (v0)

## Overview

Keeper-style liquidation: anyone can liquidate an undercollateralized position when the health factor drops below 1.0. Collateral is seized at a bonus; debt is repaid to the vault.

## Components

| Contract | Role |
|----------|------|
| **SignedPriceOracle** | EIP-712 signed price feed; collateral price in USDC terms (6 decimals) |
| **LiquidationManager** | Entrypoint for liquidation; verifies price, computes HF, pulls USDC, seizes collateral |
| **LoanEngine** | Gated hooks: `liquidationRepay`, `seizeCollateral` (callable only by LiquidationManager) |
| **TreasuryVault** | `pullFromBorrower` extended to allow LiquidationManager (in addition to LoanEngine) |

## Constants (v0)

| Parameter | Value | Description |
|-----------|-------|-------------|
| liquidationThresholdBps | 8800 (88%) | Threshold at which liquidation is allowed (of LTV at origination) |
| closeFactorBps | 5000 (50%) | Max fraction of principal repayable per liquidation |
| liquidationBonusBps | 800 (8%) | Bonus paid to liquidator on seized collateral |
| minHealthFactor | 1e18 | HF must be &lt; 1e18 to liquidate |

## Price Model

- **Unit**: collateral price in USDC terms, 6 decimals
- **Example**: 1 collateral = 1.00 USDC → `price = 1_000_000`; 50% drop → `price = 500_000`
- **Collateral value**:
  ```
  collateralValueUSDC = collateralAmount(18) * price(6) / 1e18
  ```

## Health Factor (HF)

HF is scaled by 1e18. Liquidate when HF &lt; 1e18.

```
HF = (collateralValueUSDC * liquidationThresholdBps * 1e18) / (10_000 * principalUSDC)
```

Interpretation:
- HF &gt; 1e18 → healthy (no liquidation)
- HF &lt; 1e18 → liquidatable

## Liquidation Flow

1. **Update price**: Liquidator passes `PricePayload` + signature → `SignedPriceOracle.verifyPricePayload` (consumes nonce, stores latest price)
2. **Check HF**: Compute HF with current price; revert if HF ≥ 1e18
3. **Cap repay**: `repayAmount ≤ principal * closeFactorBps / 10_000`
4. **Pull USDC**: `vault.pullFromBorrower(liquidator, repayAmount)` — liquidator must approve vault
5. **Reduce principal**: `loanEngine.liquidationRepay(borrower, repayAmount)`
6. **Seize collateral**:
   ```
   collateralToSeize = (repayAmount * 1e18 * (10_000 + bonusBps)) / (price * 10_000)
   ```
   Capped at borrower's collateral balance.

## SignedPriceOracle (EIP-712)

Same trust pattern as RiskOracle:
- Per-asset nonce
- 5-minute validity window
- Stores latest price + timestamp on verification
- Swap to Chainlink later with same interface (`IPriceOracle`)

## LoanEngine Hooks (Gated)

| Function | Caller | Effect |
|----------|--------|--------|
| `liquidationRepay(borrower, amount)` | LiquidationManager only | Reduces principal; no approval (funds already in vault) |
| `seizeCollateral(borrower, to, amount)` | LiquidationManager only | Decreases collateral balance; transfers token to `to` |

Events: `LiquidationRepay`, `CollateralSeized`, `LiquidationManagerSet`.
