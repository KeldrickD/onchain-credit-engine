/**
 * Example: Integrate OCX into a lending pool / origination gate in ~30 lines.
 *
 * Prerequisites:
 * - CreditRegistry, RiskEngineV2, RiskOracle deployed
 * - Offchain signer (oracle) that produces signed RiskPayloadV2 or RiskPayloadV2ByKey
 *
 * Flow:
 * 1. User or subject has been evaluated; signer returns payload + signature.
 * 2. Frontend or backend calls CreditRegistry.updateCreditProfileV2ByKey(payload, signature).
 * 3. Lending pool checks CreditRegistry.getProfile(subjectKey) and gates by tier/score.
 */

import { buildRiskPayloadV2ByKey } from "../src/payload.js";
import { hashReasons, hashEvidence } from "../src/hash.js";
import { riskPayloadV2ByKeyTypedData, riskOracleDomain } from "../src/sign.js";
import { type Hex } from "../src/types.js";

// ---------------------------------------------------------------------------
// 1) Build payload (same shape the oracle signer would produce)
// ---------------------------------------------------------------------------
const subjectKey = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" as Hex;
const reasonCodes = [
  "0x" + "a".repeat(64),
  "0x" + "b".repeat(64),
] as Hex[];
const evidence = ["0x" + "c".repeat(64)] as Hex[];

const payload = buildRiskPayloadV2ByKey({
  subjectKey,
  score: 720,
  riskTier: 2,
  confidenceBps: 7500,
  modelId: "0x" + "d".repeat(64) as Hex,
  reasonCodes,
  evidence,
  timestamp: BigInt(Math.floor(Date.now() / 1000)),
  nonce: 1n,
});

// ---------------------------------------------------------------------------
// 2) Sign (in practice: oracle signer holds private key; client sends subjectId, gets payload + sig)
// ---------------------------------------------------------------------------
const chainId = 84532;
const riskOracleAddress = "0x0000000000000000000000000000000000000000" as Hex; // set after deploy
const domain = riskOracleDomain(chainId, riskOracleAddress);
const typedData = riskPayloadV2ByKeyTypedData(domain, payload);

// With viem: const signature = await walletClient.signTypedData(typedData);
// Oracle signer returns { payload, signature }; client submits to CreditRegistry.

// ---------------------------------------------------------------------------
// 3) Verify offchain (viem verifyTypedData) before submitting
// ---------------------------------------------------------------------------
// import { verifyTypedData } from "viem";
// const valid = await verifyTypedData({ ...typedData, signature, address: expectedSigner });

// ---------------------------------------------------------------------------
// 4) Lending gate: read profile, allow only tier 2+ and score >= 600
// ---------------------------------------------------------------------------
// const profile = await publicClient.readContract({
//   address: creditRegistryAddress,
//   abi: creditRegistryAbi,
//   functionName: "getProfile",
//   args: [subjectKey],
// });
// if (Number(profile.riskTier) >= 2 && Number(profile.score) >= 600) {
//   // allow borrow
// }

console.log("Payload built:", payload);
console.log("Typed data for signTypedData:", JSON.stringify(typedData, (_, v) => (typeof v === "bigint" ? v.toString() : v), 2));
console.log("Hash helpers: reasonsHash/evidenceHash are inside payload.reasonsHash, payload.evidenceHash");
