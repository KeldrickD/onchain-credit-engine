/**
 * EIP-712 signing and verification for OCX risk payloads (v2ByKey).
 * Use with viem: signTypedData, verifyTypedData.
 */
import type { Hex } from "./types.js";
import type { RiskPayloadV2ByKey } from "./types.js";
import type { EIP712Domain } from "./types.js";
export declare const RISK_PAYLOAD_V2_BY_KEY_TYPE: {
    readonly RiskPayloadV2ByKey: readonly [{
        readonly name: "subjectKey";
        readonly type: "bytes32";
    }, {
        readonly name: "score";
        readonly type: "uint16";
    }, {
        readonly name: "riskTier";
        readonly type: "uint8";
    }, {
        readonly name: "confidenceBps";
        readonly type: "uint16";
    }, {
        readonly name: "modelId";
        readonly type: "bytes32";
    }, {
        readonly name: "reasonsHash";
        readonly type: "bytes32";
    }, {
        readonly name: "evidenceHash";
        readonly type: "bytes32";
    }, {
        readonly name: "timestamp";
        readonly type: "uint64";
    }, {
        readonly name: "nonce";
        readonly type: "uint64";
    }];
};
/**
 * Domain for Risk Oracle EIP-712. Must match onchain RiskOracle domain.
 */
export declare function riskOracleDomain(chainId: number, verifyingContract: Hex): EIP712Domain;
/**
 * Message for signTypedData (viem). Use with primaryType "RiskPayloadV2ByKey".
 */
export declare function riskPayloadV2ByKeyMessage(payload: RiskPayloadV2ByKey): {
    subjectKey: `0x${string}`;
    score: number;
    riskTier: number;
    confidenceBps: number;
    modelId: `0x${string}`;
    reasonsHash: `0x${string}`;
    evidenceHash: `0x${string}`;
    timestamp: bigint;
    nonce: bigint;
};
/**
 * Full typed data for viem signTypedData / verifyTypedData.
 */
export declare function riskPayloadV2ByKeyTypedData(domain: EIP712Domain, payload: RiskPayloadV2ByKey): {
    domain: {
        name: string;
        version: string;
        chainId: number;
        verifyingContract: `0x${string}`;
    };
    types: {
        readonly RiskPayloadV2ByKey: readonly [{
            readonly name: "subjectKey";
            readonly type: "bytes32";
        }, {
            readonly name: "score";
            readonly type: "uint16";
        }, {
            readonly name: "riskTier";
            readonly type: "uint8";
        }, {
            readonly name: "confidenceBps";
            readonly type: "uint16";
        }, {
            readonly name: "modelId";
            readonly type: "bytes32";
        }, {
            readonly name: "reasonsHash";
            readonly type: "bytes32";
        }, {
            readonly name: "evidenceHash";
            readonly type: "bytes32";
        }, {
            readonly name: "timestamp";
            readonly type: "uint64";
        }, {
            readonly name: "nonce";
            readonly type: "uint64";
        }];
    };
    primaryType: "RiskPayloadV2ByKey";
    message: {
        subjectKey: `0x${string}`;
        score: number;
        riskTier: number;
        confidenceBps: number;
        modelId: `0x${string}`;
        reasonsHash: `0x${string}`;
        evidenceHash: `0x${string}`;
        timestamp: bigint;
        nonce: bigint;
    };
};
//# sourceMappingURL=sign.d.ts.map