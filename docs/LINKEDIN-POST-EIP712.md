# LinkedIn Post — EIP-712 Oracle Milestone

---

**Onchain Credit Engine (OCX)** — real-time credit scoring for stablecoin lending.

Shipped the oracle layer:

✅ **EIP-712 signed risk payloads** — domain separator, typed data hashing, clean verification  
✅ **Replay protection** — per-user nonce, consumed on first use  
✅ **CreditRegistry** — storage gated by oracle; atomic verify + store  
✅ **23 tests** — valid/invalid signer, expired timestamp, replay, bounds, independence  

Design choice: RiskOracle does `verifyRiskPayload` (consumes) + `verifyRiskPayloadView` (precheck). CreditRegistry only calls the consuming path — one state transition, no races.

Built for protocol engineers + fintech risk. Base Sepolia first; zkSync post-MVP.

#DeFi #Web3 #SmartContracts #Ethereum #ProtocolEngineering
