# OCX Deployments

## Base Sepolia

| Contract | Address |
|----------|---------|
| MockUSDC | _TBD_ |
| MockCollateral | _TBD_ |
| TreasuryVault | _TBD_ |
| RiskOracle | _TBD_ |
| CreditRegistry | _TBD_ |
| LoanEngine | _TBD_ |

### Deploy Order

1. MockUSDC, MockCollateral
2. TreasuryVault(usdc, owner) — fund with USDC
3. RiskOracle(oracleSigner)
4. CreditRegistry(riskOracle)
5. PriceRouter, CollateralManager, SignedPriceOracle (or Chainlink feeds)
6. LoanEngine(creditRegistry, vault, usdc, priceRouter, collateralManager)
7. `vault.setLoanEngine(loanEngine)`, `collateralManager.setLoanEngine(loanEngine)` (owner)
8. LiquidationManager(loanEngine, collateralManager, usdc, vault, priceRouter)

### Post-Deploy

- Fund vault with USDC (or have LPs deposit)
- Fund oracle signer for gas
- Run `backend/oracle-signer` with RISK_SIGNER_PRIVATE_KEY, PRICE_SIGNER_PRIVATE_KEY

### Oracle Signer Backend

For borrow flow, the frontend calls `POST /risk/sign` to get a signed risk payload. The backend:
- Fetches an unused nonce from `RiskOracle.isNonceUsed(user, nonce)`
- Signs EIP-712 with the oracle key
- Returns `{ payload, signature }`

For price (admin/dev): `POST /price/sign` with `{ asset, priceUSD8 }`. Fetches nonce from `SignedPriceOracle.isNonceUsed(asset, nonce)`.
