/**
 * EIP-712 signing and verification helpers for OCX risk payloads.
 * Use with viem: signTypedData, verifyTypedData.
 */
export const RISK_PAYLOAD_V2_TYPE = {
    RiskPayloadV2: [
        { name: "user", type: "address" },
        { name: "score", type: "uint16" },
        { name: "riskTier", type: "uint8" },
        { name: "confidenceBps", type: "uint16" },
        { name: "modelId", type: "bytes32" },
        { name: "reasonsHash", type: "bytes32" },
        { name: "evidenceHash", type: "bytes32" },
        { name: "timestamp", type: "uint64" },
        { name: "nonce", type: "uint64" },
    ],
};
export const RISK_PAYLOAD_V2_BY_KEY_TYPE = {
    RiskPayloadV2ByKey: [
        { name: "subjectKey", type: "bytes32" },
        { name: "score", type: "uint16" },
        { name: "riskTier", type: "uint8" },
        { name: "confidenceBps", type: "uint16" },
        { name: "modelId", type: "bytes32" },
        { name: "reasonsHash", type: "bytes32" },
        { name: "evidenceHash", type: "bytes32" },
        { name: "timestamp", type: "uint64" },
        { name: "nonce", type: "uint64" },
    ],
};
/**
 * Domain for Risk Oracle EIP-712. Must match onchain RiskOracle domain.
 */
export function riskOracleDomain(chainId, verifyingContract) {
    return {
        name: "OCX Risk Oracle",
        version: "1",
        chainId,
        verifyingContract,
    };
}
export function riskPayloadV2Message(payload) {
    return {
        user: payload.user,
        score: payload.score,
        riskTier: payload.riskTier,
        confidenceBps: payload.confidenceBps,
        modelId: payload.modelId,
        reasonsHash: payload.reasonsHash,
        evidenceHash: payload.evidenceHash,
        timestamp: payload.timestamp,
        nonce: payload.nonce,
    };
}
export function riskPayloadV2TypedData(domain, payload) {
    return {
        domain: {
            name: domain.name,
            version: domain.version,
            chainId: domain.chainId,
            verifyingContract: domain.verifyingContract,
        },
        types: RISK_PAYLOAD_V2_TYPE,
        primaryType: "RiskPayloadV2",
        message: riskPayloadV2Message(payload),
    };
}
/**
 * Message for signTypedData (viem). Use with primaryType "RiskPayloadV2ByKey".
 */
export function riskPayloadV2ByKeyMessage(payload) {
    return {
        subjectKey: payload.subjectKey,
        score: payload.score,
        riskTier: payload.riskTier,
        confidenceBps: payload.confidenceBps,
        modelId: payload.modelId,
        reasonsHash: payload.reasonsHash,
        evidenceHash: payload.evidenceHash,
        timestamp: payload.timestamp,
        nonce: payload.nonce,
    };
}
/**
 * Full typed data for viem signTypedData / verifyTypedData.
 */
export function riskPayloadV2ByKeyTypedData(domain, payload) {
    return {
        domain: {
            name: domain.name,
            version: domain.version,
            chainId: domain.chainId,
            verifyingContract: domain.verifyingContract,
        },
        types: RISK_PAYLOAD_V2_BY_KEY_TYPE,
        primaryType: "RiskPayloadV2ByKey",
        message: riskPayloadV2ByKeyMessage(payload),
    };
}
