/**
 * Build risk payloads (v2, v2ByKey) with correct hashing.
 */
import { hashReasons, hashEvidence } from "./hash.js";
/**
 * Build RiskPayloadV2ByKey with reasonsHash and evidenceHash from arrays.
 */
export function buildRiskPayloadV2ByKey(params) {
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
