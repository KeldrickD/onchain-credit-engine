// Extracted from contracts/out/CreditRegistry.sol/CreditRegistry.json
export const creditRegistryAbi = [
  {
    inputs: [{ internalType: "address", name: "user", type: "address" }],
    name: "getCreditProfile",
    outputs: [
      {
        components: [
          { internalType: "uint256", name: "score", type: "uint256" },
          { internalType: "uint256", name: "riskTier", type: "uint256" },
          { internalType: "uint256", name: "lastUpdated", type: "uint256" },
          { internalType: "bytes32", name: "modelId", type: "bytes32" },
          { internalType: "uint16", name: "confidenceBps", type: "uint16" },
          { internalType: "bytes32", name: "reasonsHash", type: "bytes32" },
          { internalType: "bytes32", name: "evidenceHash", type: "bytes32" },
        ],
        internalType: "struct ICreditRegistry.CreditProfile",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        components: [
          { internalType: "address", name: "user", type: "address" },
          { internalType: "uint16", name: "score", type: "uint16" },
          { internalType: "uint8", name: "riskTier", type: "uint8" },
          { internalType: "uint16", name: "confidenceBps", type: "uint16" },
          { internalType: "bytes32", name: "modelId", type: "bytes32" },
          { internalType: "bytes32", name: "reasonsHash", type: "bytes32" },
          { internalType: "bytes32", name: "evidenceHash", type: "bytes32" },
          { internalType: "uint64", name: "timestamp", type: "uint64" },
          { internalType: "uint64", name: "nonce", type: "uint64" },
        ],
        internalType: "struct IRiskOracle.RiskPayloadV2",
        name: "payload",
        type: "tuple",
      },
      { internalType: "bytes", name: "signature", type: "bytes" },
    ],
    name: "updateCreditProfileV2",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
