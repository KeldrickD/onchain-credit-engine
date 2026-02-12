# Base Sepolia Price Feed Setup

Configure PriceRouter and CollateralManager for Base Sepolia deployment. **Pull feed addresses from [Chainlink Data Feeds](https://docs.chain.link/data-feeds/price-feeds/addresses?network=base-sepolia) at deploy time** — addresses can change.

## PriceRouter Configuration

### Per-asset setup

For each supported collateral asset:

1. **Chainlink feed** — set via `setChainlinkFeed(asset, feedAddress)`
2. **Source** — `setSource(asset, Source.CHAINLINK)` for production
3. **Stale period** — `setStalePeriod(asset, seconds)` (e.g. 3600 for 1h)

### Feed validation (PriceRouter)

- `answer > 0` (reverts on zero/negative)
- `answeredInRound >= roundId` (sanity check)
- `updatedAt != 0`
- Decimals normalized to USD8 (Chainlink typically 8; non-8 feeds scaled automatically)

### Recommended stale periods

| Asset   | Stale period | Notes              |
|---------|--------------|--------------------|
| ETH/USD | 3600         | 1 hour             |
| BTC/USD | 3600         | 1 hour             |
| USDC/USD| 86400        | Lower vol, 24h ok  |

## CollateralManager Configuration

Example config per asset:

| Field                      | Example | Description                    |
|----------------------------|---------|--------------------------------|
| enabled                    | true    | Asset can accrue debt          |
| ltvBpsCap                  | 8000    | Max borrow LTV (80%)           |
| liquidationThresholdBpsCap | 8800    | Max liquidation threshold 88%  |
| haircutBps                 | 10000   | No haircut (10000 = 100%)      |
| debtCeilingUSDC6           | 500000e6| 500k USDC cap                  |

### Risk profiles (examples)

**ETH (volatile):**

- ltvBpsCap: 7500
- liquidationThresholdBpsCap: 8300
- haircutBps: 9800 (2% haircut)
- debtCeilingUSDC6: 1_000_000e6

**WBTC (volatile):**

- ltvBpsCap: 7000
- liquidationThresholdBpsCap: 8000
- haircutBps: 9500 (5% haircut)
- debtCeilingUSDC6: 500_000e6

**USDC (stable, if ever used as collateral):**

- ltvBpsCap: 9000
- liquidationThresholdBpsCap: 9500
- haircutBps: 10000
- debtCeilingUSDC6: 10_000_000e6

## Deploy order

1. Deploy PriceRouter, CollateralManager, SignedPriceOracle (fallback)
2. Configure PriceRouter: feeds, sources, stale periods
3. Configure CollateralManager: per-asset configs
4. Deploy LoanEngine with priceRouter + collateralManager
5. Call `collateralManager.setLoanEngine(loanEngine)`
6. Deploy LiquidationManager with loanEngine, collateralManager, usdc, vault, priceRouter
