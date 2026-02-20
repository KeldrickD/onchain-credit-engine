/**
 * Deterministic hashing per SPEC.md.
 * reasonsHash = keccak256(abi.encode(bytes32[])); evidenceHash = keccak256(abi.encode(bytes32[])).
 */
import type { Hex } from "./types.js";
/**
 * Hash reason codes for RiskPayloadV2 / RiskPayloadV2ByKey.
 * Order of reasonCodes matters.
 */
export declare function hashReasons(reasonCodes: readonly Hex[]): Hex;
/**
 * Hash evidence (e.g. attestation IDs) for RiskPayloadV2 / RiskPayloadV2ByKey.
 * Order matters.
 */
export declare function hashEvidence(evidence: readonly Hex[]): Hex;
//# sourceMappingURL=hash.d.ts.map