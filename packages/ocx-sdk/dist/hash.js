/**
 * Deterministic hashing per SPEC.md.
 * reasonsHash = keccak256(abi.encode(bytes32[])); evidenceHash = keccak256(abi.encode(bytes32[])).
 */
import { keccak256, encodeAbiParameters, parseAbiParameters } from "viem";
/**
 * Hash reason codes for RiskPayloadV2 / RiskPayloadV2ByKey.
 * Order of reasonCodes matters.
 */
export function hashReasons(reasonCodes) {
    return keccak256(encodeAbiParameters(parseAbiParameters("bytes32[]"), [reasonCodes]));
}
/**
 * Hash evidence (e.g. attestation IDs) for RiskPayloadV2 / RiskPayloadV2ByKey.
 * Order matters.
 */
export function hashEvidence(evidence) {
    return keccak256(encodeAbiParameters(parseAbiParameters("bytes32[]"), [evidence]));
}
