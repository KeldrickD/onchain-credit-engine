import { encodeAbiParameters, keccak256, type Hex } from "viem";

export type HostedRiskInputs = {
  kyb: boolean;
  dscr: number;
  noi: number;
  sponsorScore: number;
};

export type HostedRiskEvaluation = {
  score: number;
  tier: number;
  confidenceBps: number;
  modelId: Hex;
  reasonCodes: Hex[];
  evidence: Hex[];
};

const HOSTED_RISK_MODEL_ID = keccak256(
  new TextEncoder().encode("OCX_HOSTED_EVAL_V1")
) as Hex;

const REASONS = {
  KYB_VERIFIED: reasonCode("KYB_VERIFIED"),
  DSCR_STRONG: reasonCode("DSCR_STRONG"),
  DSCR_STABLE: reasonCode("DSCR_STABLE"),
  DSCR_THIN: reasonCode("DSCR_THIN"),
  NOI_STRONG: reasonCode("NOI_STRONG"),
  NOI_MID: reasonCode("NOI_MID"),
  NOI_STARTER: reasonCode("NOI_STARTER"),
  SPONSOR_ELITE: reasonCode("SPONSOR_ELITE"),
  SPONSOR_SOLID: reasonCode("SPONSOR_SOLID"),
  SPONSOR_FAIR: reasonCode("SPONSOR_FAIR"),
} as const;

function reasonCode(label: string): Hex {
  return keccak256(new TextEncoder().encode(label)) as Hex;
}

function evidenceEntry(label: string, value: string | number | boolean): Hex {
  return keccak256(new TextEncoder().encode(`${label}:${value}`)) as Hex;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function hashHexArray(values: readonly Hex[]): Hex {
  return keccak256(
    encodeAbiParameters([{ type: "bytes32[]" }], [values as Hex[]])
  ) as Hex;
}

export function evaluateHostedRisk(inputs: HostedRiskInputs): HostedRiskEvaluation {
  const reasonCodes: Hex[] = [];
  const evidence: Hex[] = [
    evidenceEntry("kyb", inputs.kyb),
    evidenceEntry("dscr_bps", Math.round(inputs.dscr * 10000)),
    evidenceEntry("noi_usd", Math.round(inputs.noi)),
    evidenceEntry("sponsor_score", Math.round(inputs.sponsorScore)),
  ];

  let score = 480;
  let confidenceBps = 5000;

  if (inputs.kyb) {
    score += 60;
    confidenceBps += 1000;
    reasonCodes.push(REASONS.KYB_VERIFIED);
  }

  if (inputs.dscr >= 1.75) {
    score += 80;
    confidenceBps += 1400;
    reasonCodes.push(REASONS.DSCR_STRONG);
  } else if (inputs.dscr >= 1.35) {
    score += 55;
    confidenceBps += 1100;
    reasonCodes.push(REASONS.DSCR_STABLE);
  } else if (inputs.dscr >= 1.0) {
    score += 25;
    confidenceBps += 700;
    reasonCodes.push(REASONS.DSCR_THIN);
  }

  if (inputs.noi >= 250000) {
    score += 70;
    confidenceBps += 1100;
    reasonCodes.push(REASONS.NOI_STRONG);
  } else if (inputs.noi >= 100000) {
    score += 45;
    confidenceBps += 850;
    reasonCodes.push(REASONS.NOI_MID);
  } else if (inputs.noi >= 50000) {
    score += 20;
    confidenceBps += 500;
    reasonCodes.push(REASONS.NOI_STARTER);
  }

  if (inputs.sponsorScore >= 760) {
    score += 75;
    confidenceBps += 1200;
    reasonCodes.push(REASONS.SPONSOR_ELITE);
  } else if (inputs.sponsorScore >= 720) {
    score += 55;
    confidenceBps += 900;
    reasonCodes.push(REASONS.SPONSOR_SOLID);
  } else if (inputs.sponsorScore >= 680) {
    score += 30;
    confidenceBps += 600;
    reasonCodes.push(REASONS.SPONSOR_FAIR);
  }

  score = clamp(score, 300, 900);
  confidenceBps = clamp(confidenceBps, 4000, 9500);

  let tier = 5;
  if (score >= 780) tier = 0;
  else if (score >= 720) tier = 1;
  else if (score >= 660) tier = 2;
  else if (score >= 580) tier = 3;
  else if (score >= 500) tier = 4;

  return {
    score,
    tier,
    confidenceBps,
    modelId: HOSTED_RISK_MODEL_ID,
    reasonCodes,
    evidence,
  };
}
