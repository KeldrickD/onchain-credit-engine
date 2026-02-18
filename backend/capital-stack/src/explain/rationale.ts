/**
 * Build rationale, constraints, and sensitivity notes from inputs and stack.
 * Deterministic text for institutional transparency.
 */

import type { ExtractedInputs } from "../types.js";
import type { StackPct } from "../types.js";

const DSCR_STRONG_BPS = 13500;
const DSCR_OK_MIN_BPS = 12000;

function dscrLabel(dscrBps: number | undefined): string {
  if (dscrBps == null) return "DSCR not provided";
  if (dscrBps >= DSCR_STRONG_BPS) return "DSCR strong (≥1.35)";
  if (dscrBps >= DSCR_OK_MIN_BPS) return "DSCR OK (1.20–1.35)";
  return "DSCR weak (<1.20)";
}

export function buildRationale(inputs: ExtractedInputs, stack: StackPct): string[] {
  const lines: string[] = [];
  const t = Math.max(0, Math.min(3, Math.floor(inputs.tier)));
  lines.push(`Tier ${t} base: Senior ${stack.senior}%, Mezz ${stack.mezz}%, Pref ${stack.pref}%, Common ${stack.common}%.`);
  if (inputs.dscrBps != null) {
    lines.push(dscrLabel(inputs.dscrBps) + " — applied DSCR adjustment.");
  }
  const confPct = inputs.confidenceBps / 100;
  if (confPct >= 70) {
    lines.push("High confidence (≥70%) — senior +5%, mezz -5%.");
  } else if (confPct <= 35) {
    lines.push("Low confidence (≤35%) — senior -5%, pref +5%.");
  }
  if (!inputs.flags.kybPass) {
    lines.push("KYB not on file — senior -5%, pref +5%.");
  }
  if (inputs.flags.sponsorTrack) {
    lines.push("Sponsor track present — senior +5%, common -5%.");
  }
  return lines;
}

export function buildConstraints(stack: StackPct): string[] {
  const c: string[] = [];
  c.push("Senior: 15–80%; Mezz: 0–30%; Pref: 0–25%; Common: 5–60%.");
  c.push("Stack normalized to 100%.");
  return c;
}

export function buildSensitivity(): { knobs: string[]; notes: string[] } {
  return {
    knobs: ["seniorBiasBps (-2000 to +2000)", "mezzCapPct", "prefMinPct"],
    notes: [
      "Pricing is single-point estimate from tier + DSCR + confidence.",
      "Common is residual; no explicit rate.",
    ],
  };
}
