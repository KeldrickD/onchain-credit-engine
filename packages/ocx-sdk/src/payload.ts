/**
 * Build risk payloads (v2, v2ByKey) with correct hashing.
 */

import type { Hex } from "./types.js";
import type { RiskPayloadV2ByKey } from "./types.js";
import { hashReasons, hashEvidence } from "./hash.js";

export type BuildRiskPayloadV2ByKeyParams = {
  subjectKey: Hex;
  score: number;
  riskTier: number;
  confidenceBps: number;
  modelId: Hex;
  reasonCodes: readonly Hex[];
  evidence: readonly Hex[];
  timestamp: bigint;
  nonce: bigint;
};

/**
 * Build RiskPayloadV2ByKey with reasonsHash and evidenceHash from arrays.
 */
export function buildRiskPayloadV2ByKey(
  params: BuildRiskPayloadV2ByKeyParams
): RiskPayloadV2ByKey {
  return {
    subjectKey: params.subjectKey,
    score: params.score,
    riskTier: params.riskTier,
    confidenceBps: params.confidenceBps,
    modelId: params.modelId,
    reasonsHash: hashReasons(params.reasonCodes),
    evidenceHash: hashEvidence(params.evidence),
    timestamp: params.timestamp,
    nonce: params.nonce,
  };
}
