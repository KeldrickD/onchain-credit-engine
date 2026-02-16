// Extracted from contracts/out/PriceRouter.sol/PriceRouter.json
export const priceRouterAbi = [
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getPriceUSD8",
    outputs: [
      { internalType: "uint256", name: "priceUSD8", type: "uint256" },
      { internalType: "uint256", name: "updatedAt", type: "uint256" },
      { internalType: "bool", name: "isStale", type: "bool" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getSource",
    outputs: [{ internalType: "enum IPriceRouter.Source", name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getStalePeriod",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getChainlinkFeed",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getSignedOracle",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      {
        components: [
          { internalType: "address", name: "asset", type: "address" },
          { internalType: "uint256", name: "price", type: "uint256" },
          { internalType: "uint256", name: "timestamp", type: "uint256" },
          { internalType: "uint256", name: "nonce", type: "uint256" },
        ],
        internalType: "struct IPriceOracle.PricePayload",
        name: "payload",
        type: "tuple",
      },
      { internalType: "bytes", name: "signature", type: "bytes" },
    ],
    name: "updateSignedPriceAndGet",
    outputs: [{ internalType: "uint256", name: "priceUSD8", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      { internalType: "enum IPriceRouter.Source", name: "source", type: "uint8" },
    ],
    name: "setSource",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      { internalType: "address", name: "feed", type: "address" },
    ],
    name: "setChainlinkFeed",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      { internalType: "address", name: "oracle", type: "address" },
    ],
    name: "setSignedOracle",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "asset", type: "address" },
      { internalType: "uint256", name: "seconds_", type: "uint256" },
    ],
    name: "setStalePeriod",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
