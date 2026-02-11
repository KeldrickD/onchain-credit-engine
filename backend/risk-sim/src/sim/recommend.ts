/**
 * Parameter recommendation - heuristic v0
 * Grid search over threshold; penalty-based selection
 */

import { LIQUIDATION } from "../config/protocol.js";
import type { LiquidationOverrides } from "./monte-carlo.js";
import type { SimConfig } from "./monte-carlo.js";
import { DEFAULT_SIM_CONFIG } from "./monte-carlo.js";
import { runSimulation } from "./runner.js";
import type { SimulationResult } from "./runner.js";
import type { PortfolioParams } from "../models/portfolio.js";
import { DEFAULT_PORTFOLIO } from "../models/portfolio.js";

export interface RecommendTargets {
  maxExpectedLossPct: number;
  maxLiquidationFrequency: number;
  maxP95DrawdownPct: number;
}

export const DEFAULT_TARGETS: RecommendTargets = {
  maxExpectedLossPct: 10,
  maxLiquidationFrequency: 0.2,
  maxP95DrawdownPct: 50,
};

export interface SensitivityPoint {
  thresholdBps: number;
  liqFreq: number;
  EL: number;
  p95Drawdown: number;
  penalty: number;
}

export interface UtilizationSensitivityPoint {
  utilizationMean: number;
  liqFreq: number;
  EL: number;
}

export interface LtvSensitivityPoint {
  ltvMultiplier: number;
  liqFreq: number;
  EL: number;
}

export interface Recommendations {
  target: RecommendTargets;
  current: { liquidationThresholdBps: number; closeFactorBps: number; bonusBps: number };
  proposed: { liquidationThresholdBps: number; closeFactorBps: number; bonusBps: number };
  rationale: string[];
  sensitivity: {
    thresholdBpsCandidates: number[];
    summary: Array<{ thresholdBps: number; liqFreq: number; EL: number }>;
    full: SensitivityPoint[];
  };
  /** Utilization sweep: shows leverage when threshold has low impact */
  utilizationSensitivity?: UtilizationSensitivityPoint[];
  /** LTV multiplier sweep */
  ltvSensitivity?: LtvSensitivityPoint[];
  /** Leverage diagnostics: model behavior under stress */
  leverageNotes: string[];
  mostSensitiveInputs: string[];
  suggestedNextKnobs: string[];
}

/**
 * Penalty = 3*(liqFreq excess) + 2*(EL excess) + 1*(p95 excess)
 */
function computePenalty(
  result: SimulationResult,
  targets: RecommendTargets
): number {
  const liqExcess = Math.max(0, result.liquidationFrequency - targets.maxLiquidationFrequency);
  const elExcess = Math.max(0, result.expectedLossPct - targets.maxExpectedLossPct) / 100;
  const p95Excess = Math.max(0, result.p95Drawdown - targets.maxP95DrawdownPct) / 100;
  return 3 * liqExcess + 2 * elExcess + 1 * p95Excess;
}

/**
 * Stage A: threshold-only grid search
 * Returns best config and full sensitivity
 */
export function runRecommendation(
  runs: number,
  seed: number,
  targets: RecommendTargets = DEFAULT_TARGETS,
  portfolioParams: PortfolioParams = DEFAULT_PORTFOLIO
): { result: SimulationResult; recommendations: Recommendations } {
  const thresholdCandidates = [9000, 8800, 8600, 8400, 8200, 8000];
  const simConfig: SimConfig = { ...DEFAULT_SIM_CONFIG };

  const sensitivityPoints: SensitivityPoint[] = [];
  let bestPenalty = Infinity;
  let bestOverrides: LiquidationOverrides = {
    thresholdBps: LIQUIDATION.thresholdBps,
    closeFactorBps: LIQUIDATION.closeFactorBps,
    bonusBps: LIQUIDATION.bonusBps,
  };
  let baseResult: SimulationResult | null = null;

  for (const thresholdBps of thresholdCandidates) {
    const overrides: LiquidationOverrides = {
      thresholdBps,
      closeFactorBps: LIQUIDATION.closeFactorBps,
      bonusBps: LIQUIDATION.bonusBps,
    };
    const config = { ...simConfig, liquidationOverrides: overrides };
    const result = runSimulation(runs, seed, portfolioParams, config);
    if (thresholdBps === LIQUIDATION.thresholdBps) baseResult = result;

    const penalty = computePenalty(result, targets);
    sensitivityPoints.push({
      thresholdBps,
      liqFreq: result.liquidationFrequency,
      EL: result.expectedLossPct,
      p95Drawdown: result.p95Drawdown,
      penalty,
    });

    if (penalty < bestPenalty) {
      bestPenalty = penalty;
      bestOverrides = overrides;
    }
  }

  // Stage B: if penalty still high, reduce close factor and bonus
  let proposed = bestOverrides;
  if (bestPenalty > 0.5) {
    const reducedOverrides: LiquidationOverrides = {
      ...proposed,
      closeFactorBps: 3500,
      bonusBps: 600,
    };
    const reducedResult = runSimulation(
      runs,
      seed,
      portfolioParams,
      { ...simConfig, liquidationOverrides: reducedOverrides }
    );
    const reducedPenalty = computePenalty(reducedResult, targets);
    if (reducedPenalty < bestPenalty) {
      proposed = reducedOverrides;
    }
  }

  if (!baseResult) baseResult = runSimulation(runs, seed, portfolioParams, simConfig);

  const rationale: string[] = [];
  if (baseResult.liquidationFrequency > targets.maxLiquidationFrequency) {
    rationale.push(
      `Liquidation frequency (${(baseResult.liquidationFrequency * 100).toFixed(2)}%) exceeds target (${targets.maxLiquidationFrequency * 100}%)`
    );
  }
  if (baseResult.expectedLossPct > targets.maxExpectedLossPct) {
    rationale.push(
      `Expected loss (${baseResult.expectedLossPct.toFixed(2)}%) exceeds target (${targets.maxExpectedLossPct}%)`
    );
  }
  if (baseResult.p95Drawdown > targets.maxP95DrawdownPct) {
    rationale.push(
      `95th percentile drawdown (${baseResult.p95Drawdown.toFixed(1)}%) exceeds target (${targets.maxP95DrawdownPct}%)`
    );
  }
  rationale.push(
    "Adjusting threshold affects liquidation buffer; lowering close factor reduces cascade risk; lowering bonus reduces liquidator extraction"
  );

  const summary = sensitivityPoints
    .filter((p, i) => i % 2 === 0 || p.thresholdBps === proposed.thresholdBps)
    .map((p) => ({
      thresholdBps: p.thresholdBps,
      liqFreq: Math.round(p.liqFreq * 100) / 100,
      EL: Math.round(p.EL * 100) / 100,
    }))
    .slice(0, 6);

  // Utilization sensitivity (knobs that move outcomes)
  const utilizationCandidates = [0.45, 0.6, 0.75];
  const utilizationSensitivity: UtilizationSensitivityPoint[] = [];
  for (const u of utilizationCandidates) {
    const params = { ...portfolioParams, utilizationMean: u, utilizationStd: 0.1 };
    const res = runSimulation(runs, seed, params, simConfig);
    utilizationSensitivity.push({
      utilizationMean: u,
      liqFreq: Math.round(res.liquidationFrequency * 100) / 100,
      EL: Math.round(res.expectedLossPct * 100) / 100,
    });
  }

  // LTV multiplier sensitivity
  const ltvCandidates = [0.85, 1.0];
  const ltvSensitivity: LtvSensitivityPoint[] = [];
  for (const mult of ltvCandidates) {
    const params = { ...portfolioParams, ltvMultiplier: mult };
    const res = runSimulation(runs, seed, params, simConfig);
    ltvSensitivity.push({
      ltvMultiplier: mult,
      liqFreq: Math.round(res.liquidationFrequency * 100) / 100,
      EL: Math.round(res.expectedLossPct * 100) / 100,
    });
  }

  // Leverage diagnostics
  const thresholdLiqRange = Math.max(...sensitivityPoints.map((p) => p.liqFreq)) - Math.min(...sensitivityPoints.map((p) => p.liqFreq));
  const utilLiqRange = Math.max(...utilizationSensitivity.map((p) => p.liqFreq)) - Math.min(...utilizationSensitivity.map((p) => p.liqFreq));
  const ltvLiqRange = Math.max(...ltvSensitivity.map((p) => p.liqFreq)) - Math.min(...ltvSensitivity.map((p) => p.liqFreq));

  const leverageNotes: string[] = [];
  if (thresholdLiqRange <= 0.02) {
    leverageNotes.push(
      `Threshold sweep produced ≤2% change in liq freq (range ${(thresholdLiqRange * 100).toFixed(1)}%); model likely saturating under this stress.`
    );
  }
  if (utilLiqRange > thresholdLiqRange * 2) {
    leverageNotes.push(
      `Utilization has stronger leverage than threshold (util range ${(utilLiqRange * 100).toFixed(1)}% vs threshold ${(thresholdLiqRange * 100).toFixed(1)}%).`
    );
  }
  if (ltvLiqRange > thresholdLiqRange * 2) {
    leverageNotes.push(
      `LTV multiplier has stronger leverage than threshold (LTV range ${(ltvLiqRange * 100).toFixed(1)}% vs threshold ${(thresholdLiqRange * 100).toFixed(1)}%).`
    );
  }
  if (leverageNotes.length === 0) {
    leverageNotes.push("Parameter changes show moderate leverage under this stress model.");
  }

  const sensitivityRanges: Array<{ name: string; range: number }> = [
    { name: "utilizationMean", range: utilLiqRange },
    { name: "ltvMultiplier", range: ltvLiqRange },
    { name: "liquidationThresholdBps", range: thresholdLiqRange },
  ];
  const mostSensitiveInputs = sensitivityRanges
    .sort((a, b) => b.range - a.range)
    .map((s) => s.name);

  const suggestedNextKnobs: string[] = [];
  if (thresholdLiqRange < 0.05) {
    suggestedNextKnobs.push("reduce utilizationMean (borrowers take less risk)");
    suggestedNextKnobs.push("reduce starting LTVs via ltvMultiplier < 1");
    suggestedNextKnobs.push("add collateral haircuts in valuation");
    suggestedNextKnobs.push("soften jump parameters (jumpProbability, jumpMean)");
  }

  const recommendations: Recommendations = {
    target: targets,
    current: {
      liquidationThresholdBps: LIQUIDATION.thresholdBps,
      closeFactorBps: LIQUIDATION.closeFactorBps,
      bonusBps: LIQUIDATION.bonusBps,
    },
    proposed: {
      liquidationThresholdBps: proposed.thresholdBps,
      closeFactorBps: proposed.closeFactorBps,
      bonusBps: proposed.bonusBps,
    },
    rationale,
    sensitivity: {
      thresholdBpsCandidates: thresholdCandidates,
      summary,
      full: sensitivityPoints,
    },
    utilizationSensitivity,
    ltvSensitivity,
    leverageNotes,
    mostSensitiveInputs,
    suggestedNextKnobs,
  };

  return {
    result: baseResult,
    recommendations,
  };
}
