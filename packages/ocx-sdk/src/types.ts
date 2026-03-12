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

export type HostedRiskEvaluateRequest = {
  kyb: boolean;
  dscr: number;
  noi: number;
  sponsorScore: number;
};

export type HostedRiskEvaluateWalletRequest = HostedRiskEvaluateRequest & {
  user: Hex;
};

export type HostedRiskEvaluateSubjectRequest = HostedRiskEvaluateRequest & {
  subjectId: Hex;
};

export type HostedRiskDebug = {
  reasonCodes: Hex[];
  evidence: Hex[];
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

export type HostedRiskEvaluateResponse = {
  score: number;
  tier: number;
  confidenceBps: number;
  reasonsHash: Hex;
  evidenceHash: Hex;
  payload: RiskPayloadV2 | RiskPayloadV2ByKey;
  signature: Hex;
  debug: HostedRiskDebug;
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
