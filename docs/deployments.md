# OCX Deployments

## Base Sepolia

| Contract | Address |
|----------|---------|
| MockUSDC | _TBD_ |
| TreasuryVault | _TBD_ |
| RiskOracle | _TBD_ |
| CreditRegistry | _TBD_ |

### Deploy Order

1. MockUSDC (or use existing USDC)
2. TreasuryVault(usdc, owner)
3. RiskOracle(oracleSigner)
4. CreditRegistry(riskOracle)

### Post-Deploy

- `vault.setLoanEngine(loanEngine)` (owner)
- Fund oracle signer for gas
