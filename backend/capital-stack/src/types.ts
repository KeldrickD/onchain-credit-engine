/**
 * Capital stack suggestion API types (v0).
 * Request accepts full packet or minimal inputs; optional overrides for sensitivity.
 */

export type StackInputs = {
  requestedUSDC6: string;
  tier: number;
  score: number;
  confidenceBps: number;
  dscrBps?: number;
  noiPresent?: boolean;
  kybPass?: boolean;
  sponsorTrack?: boolean;
};

export type Overrides = {
  seniorBiasBps?: number; // -2000..+2000 (shifts senior/common)
  mezzCapPct?: number;   // default 30
  prefMinPct?: number;   // default 0
};

export type CapitalStackSuggestRequest =
  | { packet: UnderwritingPacketV0; overrides?: Overrides }
  | { inputs: StackInputs; overrides?: Overrides };

/** Minimal packet shape needed for extraction (matches frontend UnderwritingPacketV0) */
export type UnderwritingPacketV0 = {
  schema: string;
  deal: {
    dealId: string;
    requestedUSDC6: string;
  };
  creditProfileCommitted: {
    score: number;
    tier: number;
    confidenceBps: number;
  } | null;
  riskEngineLive: {
    score: number;
    tier: number;
    confidenceBps: number;
  } | null;
  attestationsLatest: Array<{
    attestationType: string;
    data: string;
  }>;
};

export type CapitalStackSuggestResponse = {
  version: "capital-stack/v0";
  dealId?: string;
  requestedUSDC6: string;
  inputs: {
    tier: number;
    score: number;
    confidenceBps: number;
    dscrBps?: number;
    flags: {
      kybPass: boolean;
      sponsorTrack: boolean;
      noiPresent: boolean;
    };
  };
  stack: {
    seniorPct: number;
    mezzPct: number;
    prefPct: number;
    commonPct: number;
    seniorUSDC6: string;
    mezzUSDC6: string;
    prefUSDC6: string;
    commonUSDC6: string;
  };
  pricing: {
    seniorAprBps: number;
    mezzAprBps: number;
    prefReturnBps: number;
  };
  constraints: string[];
  rationale: string[];
  sensitivity: {
    knobs: string[];
    notes: string[];
  };
};

export type StackPct = {
  senior: number;
  mezz: number;
  pref: number;
  common: number;
};

export type ExtractedInputs = StackInputs & {
  flags: {
    kybPass: boolean;
    sponsorTrack: boolean;
    noiPresent: boolean;
  };
};
