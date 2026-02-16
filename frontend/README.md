# OCX Frontend

Next.js 15 + wagmi + viem dashboard for the Onchain Credit Engine.

## Setup

```bash
pnpm install
cp .env.example .env.local
```

Edit `.env.local` with:

- `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL` — Base Sepolia RPC (default: https://sepolia.base.org)
- `NEXT_PUBLIC_CREDIT_REGISTRY_ADDRESS` — after deploy
- `NEXT_PUBLIC_LOAN_ENGINE_ADDRESS` — after deploy
- `NEXT_PUBLIC_PRICE_ROUTER_ADDRESS` — after deploy
- `NEXT_PUBLIC_COLLATERAL_MANAGER_ADDRESS` — after deploy
- `NEXT_PUBLIC_WETH_ADDRESS` / `NEXT_PUBLIC_WBTC_ADDRESS` — optional, for collateral config + max borrow

## Run

```bash
pnpm dev
```

## ABIs

ABIs are hand-extracted from `contracts/out/` into `src/abi/`. After contract changes, run `forge build` and update the ABI exports if needed.

## Read-only calls (Dashboard)

- `CreditRegistry.getCreditProfile(user)`
- `LoanEngine.getPosition(user)`
- `LoanEngine.getMaxBorrow(user, asset)`
- `PriceRouter.getPriceUSD8(asset)` + staleness
- `CollateralManager.getConfig(asset)`
