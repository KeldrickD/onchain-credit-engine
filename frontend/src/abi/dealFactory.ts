export const dealFactoryAbi = [
  {
    inputs: [
      { internalType: "bytes32", name: "dealType", type: "bytes32" },
      { internalType: "string", name: "metadataURI", type: "string" },
      { internalType: "address", name: "collateralAsset", type: "address" },
      { internalType: "uint256", name: "requestedUSDC6", type: "uint256" },
    ],
    name: "createDeal",
    outputs: [{ internalType: "bytes32", name: "dealId", type: "bytes32" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "bytes32", name: "dealId", type: "bytes32" },
      { internalType: "string", name: "metadataURI", type: "string" },
    ],
    name: "setDealMetadata",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "bytes32", name: "dealId", type: "bytes32" }],
    name: "deactivateDeal",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "bytes32", name: "dealId", type: "bytes32" }],
    name: "getDeal",
    outputs: [
      {
        components: [
          { internalType: "bytes32", name: "dealId", type: "bytes32" },
          { internalType: "address", name: "sponsor", type: "address" },
          { internalType: "bytes32", name: "dealType", type: "bytes32" },
          { internalType: "string", name: "metadataURI", type: "string" },
          { internalType: "address", name: "collateralAsset", type: "address" },
          { internalType: "uint256", name: "requestedUSDC6", type: "uint256" },
          { internalType: "uint64", name: "createdAt", type: "uint64" },
          { internalType: "bool", name: "active", type: "bool" },
        ],
        internalType: "struct IDealFactory.Deal",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;
