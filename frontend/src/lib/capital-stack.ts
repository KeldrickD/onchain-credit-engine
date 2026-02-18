/**
 * Capital stack suggestion API types and request/response shapes.
 * Matches backend capital-stack/v0.
 */

import type { UnderwritingPacketV0 } from "./underwriting-packet";

export type Overrides = {
  seniorBiasBps?: number;
  mezzCapPct?: number;
  prefMinPct?: number;
};

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

export type CapitalStackSuggestRequest =
  | { packet: UnderwritingPacketV0; overrides?: Overrides }
  | { inputs: StackInputs; overrides?: Overrides };

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
