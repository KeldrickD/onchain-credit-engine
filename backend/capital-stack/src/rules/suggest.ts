/**
 * Deterministic capital stack suggestion (v0).
 * No randomness, no external calls. Same inputs → same output.
 */

import type { StackPct } from "../types.js";
import { clampStack, normalizeTo100 } from "./normalize.js";
import type { ExtractedInputs } from "../types.js";

const DSCR_STRONG_BPS = 13500;  // >= 1.35
const DSCR_OK_MIN_BPS = 12000;  // 1.20–1.349
const CONFIDENCE_HIGH_PCT = 70;
const CONFIDENCE_LOW_PCT = 35;

const BASE_BY_TIER: Record<number, StackPct> = {
  3: { senior: 70, mezz: 10, pref: 10, common: 10 },
  2: { senior: 60, mezz: 15, pref: 10, common: 15 },
  1: { senior: 45, mezz: 20, pref: 10, common: 25 },
  0: { senior: 25, mezz: 20, pref: 15, common: 40 },
};

function getBase(tier: number): StackPct {
  const t = Math.max(0, Math.min(3, Math.floor(tier)));
  return { ...BASE_BY_TIER[t] ?? BASE_BY_TIER[0] };
}

function dscrBand(dscrBps: number | undefined): "strong" | "ok" | "weak" | null {
  if (dscrBps == null) return null;
  if (dscrBps >= DSCR_STRONG_BPS) return "strong";
  if (dscrBps >= DSCR_OK_MIN_BPS) return "ok";
  return "weak";
}

export function suggestStack(inputs: ExtractedInputs, overrides?: {
  seniorBiasBps?: number;
  mezzCapPct?: number;
  prefMinPct?: number;
}): StackPct {
  const base = getBase(inputs.tier);
  let senior = base.senior;
  let mezz = base.mezz;
  let pref = base.pref;
  let common = base.common;

  const dscr = dscrBand(inputs.dscrBps);
  if (dscr === "strong") {
    senior += 5;
    common -= 5;
  } else if (dscr === "weak") {
    senior -= 10;
    common += 10;
  }

  const confidencePct = inputs.confidenceBps / 100;
  if (confidencePct >= CONFIDENCE_HIGH_PCT) {
    senior += 5;
    mezz -= 5;
  } else if (confidencePct <= CONFIDENCE_LOW_PCT) {
    senior -= 5;
    pref += 5;
  }

  if (!inputs.flags.kybPass) {
    senior -= 5;
    pref += 5;
  }
  if (inputs.flags.sponsorTrack) {
    senior += 5;
    common -= 5;
  }

  let s: StackPct = { senior, mezz, pref, common };
  s = normalizeTo100(s);

  if (overrides?.seniorBiasBps != null) {
    const shift = overrides.seniorBiasBps / 10000;
    s.senior += shift;
    s.common -= shift;
  }
  if (overrides?.mezzCapPct != null && s.mezz > overrides.mezzCapPct) {
    const excess = s.mezz - overrides.mezzCapPct;
    s.mezz = overrides.mezzCapPct;
    s.common += excess;
  }
  if (overrides?.prefMinPct != null && s.pref < overrides.prefMinPct) {
    const need = overrides.prefMinPct - s.pref;
    s.pref = overrides.prefMinPct;
    s.common -= need;
  }

  return normalizeTo100(s);
}

/** Base APR by tier (midpoint of range), in bps. Senior, Mezz, Pref. */
const PRICING_BASE_BPS: Record<number, [number, number, number]> = {
  3: [900, 1350, 1100],
  2: [1100, 1650, 1300],
  1: [1350, 2000, 1500],
  0: [1650, 2500, 1800],
};

export function suggestPricing(
  inputs: ExtractedInputs,
  stack: StackPct
): { seniorAprBps: number; mezzAprBps: number; prefReturnBps: number } {
  const t = Math.max(0, Math.min(3, Math.floor(inputs.tier)));
  const [senior, mezz, pref] = PRICING_BASE_BPS[t] ?? PRICING_BASE_BPS[0];

  let seniorBps = senior;
  let mezzBps = mezz;
  const dscr = dscrBand(inputs.dscrBps);
  if (dscr === "strong") {
    seniorBps -= 150;
    mezzBps -= 150;
  } else if (dscr === "weak") {
    seniorBps += 300;
    mezzBps += 300;
  }

  const confidencePct = inputs.confidenceBps / 100;
  if (confidencePct >= CONFIDENCE_HIGH_PCT) {
    seniorBps -= 100;
    mezzBps -= 100;
  } else if (confidencePct <= CONFIDENCE_LOW_PCT) {
    seniorBps += 200;
    mezzBps += 200;
  }

  return {
    seniorAprBps: Math.round(seniorBps),
    mezzAprBps: Math.round(mezzBps),
    prefReturnBps: Math.round(pref),
  };
}
