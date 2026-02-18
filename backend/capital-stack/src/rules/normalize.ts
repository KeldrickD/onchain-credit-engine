/**
 * Clamp tranche percentages and renormalize to 100.
 * Deterministic; no randomness.
 */

const SENIOR_MIN = 15;
const SENIOR_MAX = 80;
const MEZZ_MIN = 0;
const MEZZ_MAX = 30;
const PREF_MIN = 0;
const PREF_MAX = 25;
const COMMON_MIN = 5;
const COMMON_MAX = 60;

export type StackPct = {
  senior: number;
  mezz: number;
  pref: number;
  common: number;
};

export function clampStack(s: StackPct): StackPct {
  return {
    senior: Math.max(SENIOR_MIN, Math.min(SENIOR_MAX, Math.round(s.senior * 100) / 100)),
    mezz: Math.max(MEZZ_MIN, Math.min(MEZZ_MAX, Math.round(s.mezz * 100) / 100)),
    pref: Math.max(PREF_MIN, Math.min(PREF_MAX, Math.round(s.pref * 100) / 100)),
    common: Math.max(COMMON_MIN, Math.min(COMMON_MAX, Math.round(s.common * 100) / 100)),
  };
}

/**
 * Normalize so senior + mezz + pref + common = 100.
 * Distribute residual proportionally to avoid one tranche absorbing all rounding.
 */
export function normalizeTo100(s: StackPct): StackPct {
  const sum = s.senior + s.mezz + s.pref + s.common;
  if (sum <= 0) return s;
  const scale = 100 / sum;
  const out: StackPct = {
    senior: Math.round(s.senior * scale * 100) / 100,
    mezz: Math.round(s.mezz * scale * 100) / 100,
    pref: Math.round(s.pref * scale * 100) / 100,
    common: Math.round(s.common * scale * 100) / 100,
  };
  const outSum = out.senior + out.mezz + out.pref + out.common;
  const diff = 100 - outSum;
  if (diff !== 0) {
    out.common += diff;
    out.common = Math.round(out.common * 100) / 100;
  }
  return clampStack(out);
}
