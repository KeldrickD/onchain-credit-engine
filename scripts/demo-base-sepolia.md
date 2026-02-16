# Base Sepolia Demo Checklist

End-to-end OCX demo: deploy → config → borrow → price drop → liquidate → monitor export.

## Prerequisites

- Deploy contracts to Base Sepolia (or use existing deployments)
- Set `.env.local` in `frontend/` with contract addresses and `NEXT_PUBLIC_ADMIN_ADDRESS`
- Oracle signer backend running (`pnpm oracle-signer`)
- Frontend running (`pnpm frontend`)

## 1. Mint collateral + vault liquidity

- Mint mock WETH/WBTC to owner and borrowers (scripts or console)
- Approve and deposit USDC into TreasuryVault

## 2. Set collateral config + router source

1. Go to `/admin` and connect with admin wallet
2. **Section 3 — Collateral Risk Config**  
   - Select WETH (or WBTC)  
   - Enable, set haircut/LTV/liquidation cap/debt ceiling  
   - Save config
3. **Section 4 — Router Config**  
   - Set signed oracle address per asset  
   - Set source to SIGNED  
   - Set stale period (e.g. 3600)

## 3. Open loan

1. Go to `/borrow`  
2. Deposit collateral  
3. Get risk signature (backend must be running)  
4. Open loan

## 4. Update price down (SIGNED) and liquidate

1. Go to `/admin`  
2. **Section 2 — Price Updates**  
   - Enter lower price (e.g. 0.8 if WETH was 1.0)  
   - Submit tx to update signed price
3. Position becomes liquidatable
4. Run liquidation (keeper or manual call)

## 5. Run monitor → incident export

```bash
pnpm monitor -- --rpc $BASE_SEPOLIA_RPC_URL --lookback 5000 --step 1000
```

Export incident data for audit/triage.
