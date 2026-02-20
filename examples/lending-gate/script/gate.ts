import {
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { hashEvidence, hashReasons } from "../../../packages/ocx-sdk/src/hash.ts";

const creditRegistryAbi = parseAbi([
  "function getCreditProfile(address user) view returns ((uint256 score,uint256 riskTier,uint256 lastUpdated,bytes32 modelId,uint16 confidenceBps,bytes32 reasonsHash,bytes32 evidenceHash))",
  "function getProfile(bytes32 key) view returns ((uint256 score,uint256 riskTier,uint256 lastUpdated,bytes32 modelId,uint16 confidenceBps,bytes32 reasonsHash,bytes32 evidenceHash))",
  "function updateCreditProfileV2((address user,uint16 score,uint8 riskTier,uint16 confidenceBps,bytes32 modelId,bytes32 reasonsHash,bytes32 evidenceHash,uint64 timestamp,uint64 nonce),bytes signature)",
  "function updateCreditProfileV2ByKey((bytes32 subjectKey,uint16 score,uint8 riskTier,uint16 confidenceBps,bytes32 modelId,bytes32 reasonsHash,bytes32 evidenceHash,uint64 timestamp,uint64 nonce),bytes signature)",
]);

type CreditProfile = {
  score: bigint;
  riskTier: bigint;
  lastUpdated: bigint;
  modelId: Hex;
  confidenceBps: number;
  reasonsHash: Hex;
  evidenceHash: Hex;
};

type WalletPayload = {
  user: Address;
  score: number;
  riskTier: number;
  confidenceBps: number;
  modelId: Hex;
  reasonsHash: Hex;
  evidenceHash: Hex;
  timestamp: bigint;
  nonce: bigint;
};

type KeyPayload = {
  subjectKey: Hex;
  score: number;
  riskTier: number;
  confidenceBps: number;
  modelId: Hex;
  reasonsHash: Hex;
  evidenceHash: Hex;
  timestamp: bigint;
  nonce: bigint;
};

const mode = process.argv[2] ?? "help";

if (mode === "help") {
  printHelp();
  process.exit(0);
}

const rpcUrl = required("RPC_URL");
const creditRegistry = required("CREDIT_REGISTRY") as Address;

const minScore = Number(process.env.MIN_SCORE ?? "600");
const maxTier = Number(process.env.MAX_TIER ?? "2");
const useConfidence = (process.env.USE_CONFIDENCE ?? "false").toLowerCase() === "true";
const minConfidenceBps = Number(process.env.MIN_CONFIDENCE_BPS ?? "5000");

const publicClient = createPublicClient({ transport: http(rpcUrl) });

if (mode === "wallet") {
  const wallet = required("WALLET") as Address;
  const profile = (await publicClient.readContract({
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getCreditProfile",
    args: [wallet],
  })) as CreditProfile;
  printResult("wallet", wallet, profile);
  process.exit(0);
}

if (mode === "key") {
  const subjectKey = required("SUBJECT_KEY") as Hex;
  const profile = (await publicClient.readContract({
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getProfile",
    args: [subjectKey],
  })) as CreditProfile;
  printResult("key", subjectKey, profile);
  process.exit(0);
}

if (mode === "commit:wallet") {
  const wallet = required("WALLET") as Address;
  const signerBaseUrl = required("ORACLE_SIGNER_URL");
  const privateKey = toHexKey(required("PRIVATE_KEY"));
  const walletClient = createWalletClient({
    account: privateKeyToAccount(privateKey),
    transport: http(rpcUrl),
  });

  const before = (await publicClient.readContract({
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getCreditProfile",
    args: [wallet],
  })) as CreditProfile;
  printResult("wallet before", wallet, before);

  const res = await fetch(`${signerBaseUrl}/risk/evaluate-and-sign`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ user: wallet }),
  });
  if (!res.ok) {
    throw new Error(`oracle-signer returned ${res.status}: ${await res.text()}`);
  }
  const json = (await res.json()) as {
    payload: {
      user: Address;
      score: string;
      riskTier: string;
      confidenceBps: string;
      modelId: Hex;
      reasonsHash: Hex;
      evidenceHash: Hex;
      timestamp: string;
      nonce: string;
    };
    signature: Hex;
    debug?: { reasonCodes: Hex[]; evidence: Hex[] };
  };

  const payload: WalletPayload = {
    user: json.payload.user,
    score: Number(json.payload.score),
    riskTier: Number(json.payload.riskTier),
    confidenceBps: Number(json.payload.confidenceBps),
    modelId: json.payload.modelId,
    reasonsHash: json.payload.reasonsHash,
    evidenceHash: json.payload.evidenceHash,
    timestamp: BigInt(json.payload.timestamp),
    nonce: BigInt(json.payload.nonce),
  };
  verifyDeterministicHashes(payload.reasonsHash, payload.evidenceHash, json.debug);

  const txHash = await walletClient.writeContract({
    chain: null,
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "updateCreditProfileV2",
    args: [payload, json.signature],
  });
  await publicClient.waitForTransactionReceipt({ hash: txHash });
  console.log(`Committed wallet profile tx: ${txHash}`);

  const after = (await publicClient.readContract({
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getCreditProfile",
    args: [wallet],
  })) as CreditProfile;
  printResult("wallet after", wallet, after);
  process.exit(0);
}

if (mode === "commit:key") {
  const subjectKey = required("SUBJECT_KEY") as Hex;
  const signerBaseUrl = required("ORACLE_SIGNER_URL");
  const privateKey = toHexKey(required("PRIVATE_KEY"));
  const walletClient = createWalletClient({
    account: privateKeyToAccount(privateKey),
    transport: http(rpcUrl),
  });

  const before = (await publicClient.readContract({
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getProfile",
    args: [subjectKey],
  })) as CreditProfile;
  printResult("key before", subjectKey, before);

  const res = await fetch(`${signerBaseUrl}/risk/evaluate-subject-and-sign`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ subjectId: subjectKey }),
  });
  if (!res.ok) {
    throw new Error(`oracle-signer returned ${res.status}: ${await res.text()}`);
  }
  const json = (await res.json()) as {
    payload: {
      subjectKey: Hex;
      score: string;
      riskTier: string;
      confidenceBps: string;
      modelId: Hex;
      reasonsHash: Hex;
      evidenceHash: Hex;
      timestamp: string;
      nonce: string;
    };
    signature: Hex;
    debug?: { reasonCodes: Hex[]; evidence: Hex[] };
  };

  const payload: KeyPayload = {
    subjectKey: json.payload.subjectKey,
    score: Number(json.payload.score),
    riskTier: Number(json.payload.riskTier),
    confidenceBps: Number(json.payload.confidenceBps),
    modelId: json.payload.modelId,
    reasonsHash: json.payload.reasonsHash,
    evidenceHash: json.payload.evidenceHash,
    timestamp: BigInt(json.payload.timestamp),
    nonce: BigInt(json.payload.nonce),
  };
  verifyDeterministicHashes(payload.reasonsHash, payload.evidenceHash, json.debug);

  const txHash = await walletClient.writeContract({
    chain: null,
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "updateCreditProfileV2ByKey",
    args: [payload, json.signature],
  });
  await publicClient.waitForTransactionReceipt({ hash: txHash });
  console.log(`Committed key profile tx: ${txHash}`);

  const after = (await publicClient.readContract({
    address: creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getProfile",
    args: [subjectKey],
  })) as CreditProfile;
  printResult("key after", subjectKey, after);
  process.exit(0);
}

printHelp();
process.exit(1);

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing env var: ${name}`);
  return value;
}

function toHexKey(value: string): Hex {
  return (value.startsWith("0x") ? value : `0x${value}`) as Hex;
}

function isEligible(profile: CreditProfile): boolean {
  if (profile.score < BigInt(minScore)) return false;
  if (profile.riskTier > BigInt(maxTier)) return false;
  if (useConfidence && profile.confidenceBps < minConfidenceBps) return false;
  return true;
}

function printResult(modeLabel: string, subject: string, profile: CreditProfile): void {
  const pass = isEligible(profile);
  console.log(`Mode: ${modeLabel}`);
  console.log(`Subject: ${subject}`);
  console.log(
    `Profile -> score=${profile.score.toString()} tier=${profile.riskTier.toString()} confidenceBps=${profile.confidenceBps}`
  );
  console.log(
    `Thresholds -> minScore=${minScore} maxTier=${maxTier} useConfidence=${useConfidence} minConfidenceBps=${minConfidenceBps}`
  );
  console.log(`Gate: ${pass ? "PASS" : "FAIL"}`);
}

function verifyDeterministicHashes(expectedReasonsHash: Hex, expectedEvidenceHash: Hex, debug?: {
  reasonCodes: Hex[];
  evidence: Hex[];
}): void {
  if (!debug) {
    console.log("Signer debug arrays missing; skipped local reasons/evidence hash verification.");
    return;
  }

  const computedReasonsHash = hashReasons(debug.reasonCodes);
  const computedEvidenceHash = hashEvidence(debug.evidence);
  const reasonsOk = computedReasonsHash.toLowerCase() === expectedReasonsHash.toLowerCase();
  const evidenceOk = computedEvidenceHash.toLowerCase() === expectedEvidenceHash.toLowerCase();

  console.log(`Determinism check reasonsHash: ${reasonsOk ? "OK" : "MISMATCH"}`);
  console.log(`Determinism check evidenceHash: ${evidenceOk ? "OK" : "MISMATCH"}`);
}

function printHelp(): void {
  console.log("OCX lending-gate example");
  console.log("");
  console.log("Commands:");
  console.log("  pnpm gate:help");
  console.log("  pnpm gate:wallet");
  console.log("  pnpm gate:key");
  console.log("  pnpm commit:wallet");
  console.log("  pnpm commit:key");
  console.log("");
  console.log("Required env (read modes):");
  console.log("  RPC_URL, CREDIT_REGISTRY");
  console.log("  WALLET (for gate:wallet) or SUBJECT_KEY (for gate:key)");
  console.log("");
  console.log("Optional thresholds:");
  console.log("  MIN_SCORE=600 MAX_TIER=2 USE_CONFIDENCE=false MIN_CONFIDENCE_BPS=5000");
  console.log("");
  console.log("Required env (commit modes):");
  console.log("  RPC_URL, CREDIT_REGISTRY, ORACLE_SIGNER_URL, PRIVATE_KEY");
  console.log("  WALLET (for commit:wallet) or SUBJECT_KEY (for commit:key)");
}

