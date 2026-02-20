/**
 * OCX protocol types (align with SPEC.md).
 * Subject key, risk payloads (v1, v2, v2ByKey), attestation shapes.
 */

export type Hex = `0x${string}`;

export type RiskPayloadV2 = {
  user: Hex;
  score: number;
  riskTier: number;
  confidenceBps: number;
  modelId: Hex;
  reasonsHash: Hex;
  evidenceHash: Hex;
  timestamp: bigint;
  nonce: bigint;
};

export type RiskPayloadV2ByKey = {
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

export type SubjectAttestationPayload = {
  subjectId: Hex;
  attestationType: Hex;
  dataHash: Hex;
  data: Hex;
  uri: string;
  issuedAt: bigint;
  expiresAt: bigint;
  nonce: bigint;
};

export type EIP712Domain = {
  name: string;
  version: string;
  chainId: number;
  verifyingContract: Hex;
};
