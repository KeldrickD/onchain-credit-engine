# OCX Threat Model (v0)

## Trust Boundaries

| Component | Trust Assumption |
|-----------|------------------|
| **Risk Oracle signer** | Semi-trusted backend; compromised signer can mint arbitrary scores |
| **Price Oracle signer** | Semi-trusted backend; compromised signer can manipulate prices (liquidations) |
| **Contract owner** | Can set LoanEngine, LiquidationManager, oracle signers; assumed honest |
| **Liquidator** | Permissionless; economic incentive to liquidate when HF < 1 |

## Threats Considered

### 1. Oracle Replay

- **Risk**: Reuse of signed payloads
- **Mitigation**: Per-user (Risk) or per-asset (Price) nonce; consumed on first valid verification
- **Test**: `test_PricePayloadReplayFails`, `test_OpenLoan_ConsumesOracleNonce_ReplayFails`

### 2. Stale / Expired Payloads

- **Risk**: Old signatures used after validity window
- **Mitigation**: 5-minute timestamp validity; reverts if outside window
- **Test**: RiskOracle expiry tests, SignedPriceOracle validity

### 3. Unauthorized Liquidation

- **Risk**: Liquidate healthy positions or seize collateral without repayment
- **Mitigation**: HF check (revert if ≥ 1e18); close factor cap; only LiquidationManager can call `seizeCollateral` / `liquidationRepay`
- **Test**: `test_HealthyPosition_CannotBeLiquidated`, `test_OnlyLiquidationManagerCanCallSeizeCollateral`

### 4. Reentrancy (Collateral Token Callback)

- **Risk**: Malicious ERC20 with callback on transfer; attacker liquidates, receives collateral, callback reenters `liquidate` to double-seize
- **Mitigation**: `ReentrancyGuard` on LiquidationManager, LoanEngine, TreasuryVault; CEI (checks-effects-interactions) where applicable
- **Test**: `test_ReentrancyViaMaliciousCollateral_Blocked`

### 5. Price Manipulation (MVP)

- **Risk**: Centralized signer provides wrong price
- **Mitigation**: Out of scope for MVP; swap to decentralized feed (Chainlink) with same interface
- **Note**: Flash-loan style manipulation blocked by validity window + nonce; on-chain price source would be next step

### 6. TreasuryVault Unauthorized Pull

- **Risk**: Arbitrary address drains USDC via `pullFromBorrower`
- **Mitigation**: `onlyAuthorizedPuller` — only LoanEngine or LiquidationManager can call
- **Test**: `test_PullFromBorrower_NotLoanEngine_Reverts` (extended for LM as allowed puller)

## Out of Scope (v0)

- Interest accrual attacks
- Multi-collateral / multi-asset complexity
- Governance / upgrade attack surface
- Front-running / MEV (mitigation planned post-MVP)
