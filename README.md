# OCX — Onchain Credit Engine

A real-time credit scoring and underwriting protocol for stablecoin lending on EVM chains.

## Architecture

- **Smart contracts** — Credit registry, loan engine, risk oracle, liquidation, treasury
- **Backend** — Risk engine, oracle signer, event indexer
- **Frontend** — Borrower dashboard, risk transparency, admin console

## Phase 1: System foundation

### Contracts (Foundry)

Oracle-first design with EIP-712 signed risk payloads. Loans not yet implemented.

```bash
# Clone (includes forge-std submodule)
git clone --recurse-submodules https://github.com/KeldrickD/onchain-credit-engine.git
cd onchain-credit-engine/contracts

# Install Foundry (WSL2 recommended on Windows)
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc && foundryup

# Test
forge test -vvv
```

### Implemented

- `RiskOracle.sol` — Semi-trusted EIP-712 oracle; `verifyRiskPayload` (consumes nonce), `verifyRiskPayloadView`, `getPayloadDigest`
- `CreditRegistry.sol` — Stores CreditProfile; updates gated by oracle
- `TreasuryVault.sol` — USDC custody + accounting; deposit/withdraw; LoanEngine permission boundary (`transferToBorrower`, `pullFromBorrower`)
- `MockUSDC.sol` — 6 decimals, mintable (tests + Base Sepolia)
- `SignatureVerifier.sol` — EIP-712 domain separator, struct hashing, signature recovery
- Interfaces: `IRiskOracle`, `ICreditRegistry`, `ITreasuryVault`

### Tests (40 total)

**RiskOracle:** valid signature, invalid signer, expired timestamp, replay attack  
**CreditRegistry:** successful update, score/tier bounds, replay, different users  
**TreasuryVault:** deposit/withdraw, zero amount, approval required, LoanEngine permissions, `transferToBorrower`/`pullFromBorrower`

### Chain

Base Sepolia for iteration and demos. zkSync planned post-MVP.

## Repo structure

```
ocx/
├── contracts/       # Solidity (Foundry)
├── backend/         # Risk engine, oracle-signer, indexer
├── frontend/        # Borrower dashboard, admin
└── docs/            # Architecture, threat model, oracle design
```

## License

MIT
