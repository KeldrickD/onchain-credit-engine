// Extracted from contracts/out/ICollateralManager.sol/ICollateralManager.json
export const collateralManagerAbi = [
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getConfig",
    outputs: [
      {
        components: [
          { internalType: "bool", name: "enabled", type: "bool" },
          { internalType: "uint16", name: "ltvBpsCap", type: "uint16" },
          { internalType: "uint16", name: "liquidationThresholdBpsCap", type: "uint16" },
          { internalType: "uint16", name: "haircutBps", type: "uint16" },
          { internalType: "uint128", name: "debtCeilingUSDC6", type: "uint128" },
        ],
        internalType: "struct ICollateralManager.CollateralConfig",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "totalDebtUSDC6",
    outputs: [{ internalType: "uint128", name: "", type: "uint128" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      {
        components: [
          { internalType: "bool", name: "enabled", type: "bool" },
          { internalType: "uint16", name: "ltvBpsCap", type: "uint16" },
          { internalType: "uint16", name: "liquidationThresholdBpsCap", type: "uint16" },
          { internalType: "uint16", name: "haircutBps", type: "uint16" },
          { internalType: "uint128", name: "debtCeilingUSDC6", type: "uint128" },
        ],
        internalType: "struct ICollateralManager.CollateralConfig",
        name: "cfg",
        type: "tuple",
      },
    ],
    name: "setConfig",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
