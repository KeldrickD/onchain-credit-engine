import { oracleSignerUrl } from "./contracts";
import type { CapitalStackSuggestRequest, CapitalStackSuggestResponse } from "./capital-stack";

export type RiskSignResponse = {
  payload: {
    user: string;
    score: string;
    riskTier: string;
    timestamp: string;
    nonce: string;
  };
  signature: `0x${string}`;
};

export type RiskEvaluateAndSignResponse = {
  payload: {
    user: string;
    score: string;
    riskTier: string;
    confidenceBps: string;
    modelId: `0x${string}`;
    reasonsHash: `0x${string}`;
    evidenceHash: `0x${string}`;
    timestamp: string;
    nonce: string;
  };
  signature: `0x${string}`;
  debug?: {
    reasonCodes: `0x${string}`[];
    evidence: `0x${string}`[];
  };
};

export type PriceSignResponse = {
  payload: {
    asset: string;
    price: string;
    timestamp: string;
    nonce: string;
  };
  signature: `0x${string}`;
};

export async function fetchRiskSignature(
  user: string,
  score: number,
  riskTier: number
): Promise<RiskSignResponse> {
  const res = await fetch(`${oracleSignerUrl}/risk/sign`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user, score, riskTier }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Risk sign failed");
  }
  return res.json();
}

export async function fetchRiskEvaluationAndSignature(
  user: string
): Promise<RiskEvaluateAndSignResponse> {
  const res = await fetch(`${oracleSignerUrl}/risk/evaluate-and-sign`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Risk evaluate-and-sign failed");
  }
  return res.json();
}

export type RiskEvaluateSubjectAndSignResponse = {
  payload: {
    subjectKey: string;
    score: string;
    riskTier: string;
    confidenceBps: string;
    modelId: `0x${string}`;
    reasonsHash: `0x${string}`;
    evidenceHash: `0x${string}`;
    timestamp: string;
    nonce: string;
  };
  signature: `0x${string}`;
  debug?: {
    reasonCodes: `0x${string}`[];
    evidence: `0x${string}`[];
  };
};

export async function fetchRiskEvaluateSubjectAndSignature(
  subjectId: string
): Promise<RiskEvaluateSubjectAndSignResponse> {
  const res = await fetch(`${oracleSignerUrl}/risk/evaluate-subject-and-sign`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ subjectId }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Risk evaluate-subject-and-sign failed");
  }
  return res.json();
}

export async function fetchPriceSignature(
  asset: string,
  priceUSD8: string
): Promise<PriceSignResponse> {
  const res = await fetch(`${oracleSignerUrl}/price/sign`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ asset, priceUSD8 }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Price sign failed");
  }
  return res.json();
}

export type AttestationSignResponse = {
  payload: {
    subject: string;
    attestationType: string;
    dataHash: string;
    data: string;
    uri: string;
    issuedAt: string;
    expiresAt: string;
    nonce: string;
  };
  signature: `0x${string}`;
};

export type SubjectAttestationSignResponse = {
  payload: {
    subjectId: string;
    attestationType: string;
    dataHash: string;
    data: string;
    uri: string;
    issuedAt: string;
    expiresAt: string;
    nonce: string;
  };
  signature: `0x${string}`;
};

export type AttestationSignPayload = {
  subject: string;
  attestationType: string;
  dataHash: string;
  data?: string;
  uri?: string;
  expiresAt?: string;
};

export async function fetchAttestationSignature(
  subject: string,
  attestationType: string,
  dataHash: string,
  uri?: string,
  expiresAt?: string,
  data?: string
): Promise<AttestationSignResponse> {
  const res = await fetch(`${oracleSignerUrl}/attestation/sign`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      subject,
      attestationType,
      dataHash,
      data: data ?? "0",
      uri: uri ?? "",
      expiresAt: expiresAt ?? "0",
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Attestation sign failed");
  }
  return res.json();
}

export async function fetchSubjectAttestationSignature(
  subjectId: string,
  attestationType: string,
  dataHash: string,
  uri?: string,
  expiresAt?: string,
  data?: string
): Promise<SubjectAttestationSignResponse> {
  const res = await fetch(`${oracleSignerUrl}/attestation/subject-sign`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      subjectId,
      attestationType,
      dataHash,
      data: data ?? "0",
      uri: uri ?? "",
      expiresAt: expiresAt ?? "0",
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Subject attestation sign failed");
  }
  return res.json();
}

export async function checkOracleSignerHealth(): Promise<{
  ok: boolean;
  configured?: boolean;
}> {
  const res = await fetch(`${oracleSignerUrl}/health`);
  if (!res.ok) return { ok: false };
  const data = await res.json();
  return { ok: data.ok, configured: data.configured };
}

export async function postCapitalStackSuggest(
  body: CapitalStackSuggestRequest
): Promise<CapitalStackSuggestResponse> {
  const res = await fetch(`${oracleSignerUrl}/capital-stack/suggest`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error((err as { error?: string }).error ?? "Capital stack suggest failed");
  }
  return res.json();
}
