# OCX Contracts

Solidity contracts for the OCX (onchain credit) protocol. See repo root for full project docs.

### CI modes

- **Spec gate (fast):** `forge test --match-path test/RiskEngineV2_GoldenVectors.t.sol --fuzz-seed 42`
- **Full suite (CI):** `FOUNDRY_PROFILE=ci forge test --fuzz-seed 42`
