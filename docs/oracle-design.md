# OCX Risk Oracle Design

## Overview

Semi-trusted EIP-712 signed oracle. Single authorized signer (backend) initially; upgrade path to decentralized oracle later.

## EIP-712 Typed Data

### Domain

- **name**: `OCX Risk Oracle`
- **version**: `1`
- **chainId**: deployment chain
- **verifyingContract**: RiskOracle address

### RiskPayload Type

```
RiskPayload(address user,uint256 score,uint256 riskTier,uint256 timestamp,uint256 nonce)
```

### Flow

1. Backend computes risk score
2. Backend signs `RiskPayload` with EIP-712
3. User submits payload + signature onchain
4. `RiskOracle.verifyRiskPayload` verifies and consumes nonce

## Security

- **Validity window**: 5 minutes (configurable)
- **Replay**: Per-user nonce, consumed on first valid verification
- **Signer**: Immutable oracle signer set at deployment
