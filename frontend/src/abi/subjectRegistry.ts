export const subjectRegistryAbi = [
  {
    inputs: [{ internalType: "bytes32", name: "subjectType", type: "bytes32" }],
    name: "createSubjectWithNonce",
    outputs: [{ internalType: "bytes32", name: "subjectId", type: "bytes32" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "bytes32", name: "subjectId", type: "bytes32" },
      { internalType: "address", name: "caller", type: "address" },
    ],
    name: "isAuthorized",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "bytes32", name: "subjectId", type: "bytes32" }],
    name: "controllerOf",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "bytes32", name: "subjectId", type: "bytes32" }],
    name: "subjectTypeOf",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
] as const;
