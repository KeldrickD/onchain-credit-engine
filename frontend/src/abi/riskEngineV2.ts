export const riskEngineV2Abi = [
  {
    inputs: [{ internalType: "address", name: "subject", type: "address" }],
    name: "evaluate",
    outputs: [
      {
        components: [
          { internalType: "uint16", name: "score", type: "uint16" },
          { internalType: "uint8", name: "tier", type: "uint8" },
          { internalType: "uint16", name: "confidenceBps", type: "uint16" },
          { internalType: "bytes32", name: "modelId", type: "bytes32" },
          { internalType: "bytes32[]", name: "reasonCodes", type: "bytes32[]" },
          { internalType: "bytes32[]", name: "evidence", type: "bytes32[]" },
        ],
        internalType: "struct IRiskEngineV2.RiskOutput",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_DSCR_STRONG",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_DSCR_WEAK",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_HAS_LIQUIDATIONS",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_KYB_PASS",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_UTIL_HIGH",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_UTIL_LOW",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "REASON_REPAY_STALE",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

import { keccak256 } from "viem";

const REASON_MAP: [string, string][] = [
  ["KYB_PASS", "KYB passed"],
  ["DSCR_STRONG", "DSCR strong (≥1.30)"],
  ["DSCR_MID", "DSCR mid (1.15–1.29)"],
  ["DSCR_WEAK", "DSCR weak (<1.15)"],
  ["NOI_PRESENT", "NOI present"],
  ["SPONSOR_TRACK", "Sponsor track record"],
  ["HAS_LIQUIDATIONS", "Has liquidations"],
  ["UTIL_HIGH", "High utilization (>85%)"],
  ["UTIL_MID", "Mid utilization (70–85%)"],
  ["UTIL_LOW", "Low utilization (<50%)"],
  ["REPAY_STALE", "Repay stale (>30 days)"],
];

export function reasonCodeToLabel(code: string): string {
  const codeNorm = code.startsWith("0x") ? code : `0x${code}`;
  for (const [key, label] of REASON_MAP) {
    const h = keccak256(new TextEncoder().encode(key));
    if (h === codeNorm || h === code) return label;
  }
  return code.slice(0, 18) + "…";
}
