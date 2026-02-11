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
5. LoanEngine(creditRegistry, vault, usdc, collateral)
6. `vault.setLoanEngine(loanEngine)` (owner)

### Post-Deploy

- Fund vault with USDC (or have LPs deposit)
- Fund oracle signer for gas
