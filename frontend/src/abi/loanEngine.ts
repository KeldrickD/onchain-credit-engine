// Extracted from contracts/out/LoanEngine.sol/LoanEngine.json
export const loanEngineAbi = [
  {
    inputs: [{ internalType: "address", name: "user", type: "address" }],
    name: "getPosition",
    outputs: [
      {
        components: [
          { internalType: "address", name: "collateralAsset", type: "address" },
          { internalType: "uint256", name: "collateralAmount", type: "uint256" },
          { internalType: "uint256", name: "principalAmount", type: "uint256" },
          { internalType: "uint256", name: "openedAt", type: "uint256" },
          { internalType: "uint256", name: "ltvBps", type: "uint256" },
          { internalType: "uint256", name: "interestRateBps", type: "uint256" },
        ],
        internalType: "struct ILoanEngine.LoanPosition",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "user", type: "address" },
      { internalType: "address", name: "asset", type: "address" },
    ],
    name: "getMaxBorrow",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "user", type: "address" }],
    name: "getTerms",
    outputs: [
      {
        components: [
          { internalType: "uint256", name: "ltvBps", type: "uint256" },
          { internalType: "uint256", name: "interestRateBps", type: "uint256" },
        ],
        internalType: "struct ILoanEngine.LoanTerms",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "user", type: "address" }],
    name: "getPositionCollateralAsset",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
    ],
    name: "depositCollateral",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      { internalType: "uint256", name: "borrowAmountUSDC6", type: "uint256" },
      {
        components: [
          { internalType: "address", name: "user", type: "address" },
          { internalType: "uint256", name: "score", type: "uint256" },
          { internalType: "uint256", name: "riskTier", type: "uint256" },
          { internalType: "uint256", name: "timestamp", type: "uint256" },
          { internalType: "uint256", name: "nonce", type: "uint256" },
        ],
        internalType: "struct IRiskOracle.RiskPayload",
        name: "payload",
        type: "tuple",
      },
      { internalType: "bytes", name: "signature", type: "bytes" },
    ],
    name: "openLoan",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint256", name: "amount", type: "uint256" }],
    name: "repay",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
