/**
 * Monte Carlo runner - aggregates many paths
 */

import type { Borrower } from "../models/portfolio.js";
import type { RunResult } from "./monte-carlo.js";
import { runPath, type SimConfig } from "./monte-carlo.js";
import type { RNG } from "../models/distributions.js";
import type { PortfolioParams } from "../models/portfolio.js";
import { generatePortfolio } from "../models/portfolio.js";
import seedrandom from "seedrandom";

export interface SimulationResult {
  runs: number;
  seed: number;
  borrowerCount: number;
  periods: number;
  /** Fraction of runs with at least one liquidation */
  liquidationFrequency: number;
  /** Average liquidations per run (when any) */
  avgLiquidationsPerRun: number;
  /** Expected loss as fraction of total portfolio principal */
  expectedLossPct: number;
  /** 95th percentile drawdown (collateral value drop) */
  p95Drawdown: number;
  /** 99th percentile drawdown */
  p99Drawdown: number;
  /** Percentile of min HF across runs */
  minHFP50: number;
  minHFP95: number;
  minHFP99: number;
  /** Total portfolio principal (for scaling) */
  totalPrincipal: number;
  /** Worst price multiplier observed (percentile) */
  worstPriceP99: number;
  /** Raw run results for reporting */
  runResults: RunResult[];
}

export function runSimulation(
  runs: number,
  seed: number,
  portfolioParams: PortfolioParams,
  simConfig: SimConfig
): SimulationResult {
  const rngMaster = seedrandom(seed.toString());
  const borrowers = generatePortfolio(() => rngMaster(), portfolioParams);
  const totalPrincipal = borrowers.reduce((s, b) => s + b.principalAmount, 0);

  const runResults: RunResult[] = [];
  const minHFs: number[] = [];
  const worstPrices: number[] = [];
  const liquidationCounts: number[] = [];
  const lossRatios: number[] = [];

  for (let i = 0; i < runs; i++) {
    const pathRng = seedrandom(`${seed}-${i}`);
    const result = runPath(() => pathRng(), borrowers, simConfig);
    runResults.push(result);
    minHFs.push(result.minHealthFactor);
    worstPrices.push(result.worstPriceMultiplier);
    liquidationCounts.push(result.liquidations);
    if (totalPrincipal > 0) {
      lossRatios.push(result.principalLiquidated / totalPrincipal);
    }
  }

  minHFs.sort((a, b) => a - b);
  worstPrices.sort((a, b) => a - b);

  const p = (arr: number[], q: number) => arr[Math.floor(arr.length * q / 100)] ?? 0;
  const runsWithLiquidation = runResults.filter((r) => r.liquidations > 0).length;
  const liquidatingRuns = runResults.filter((r) => r.liquidations > 0);
  const avgLiqPerRun =
    liquidatingRuns.length > 0
      ? liquidatingRuns.reduce((s, r) => s + r.liquidations, 0) / liquidatingRuns.length
      : 0;

  const avgLoss =
    lossRatios.length > 0 ? lossRatios.reduce((a, b) => a + b, 0) / lossRatios.length : 0;

  return {
    runs,
    seed,
    borrowerCount: borrowers.length,
    periods: simConfig.periods,
    liquidationFrequency: runsWithLiquidation / runs,
    avgLiquidationsPerRun: avgLiqPerRun,
    expectedLossPct: avgLoss * 100,
    p95Drawdown: (1 - p(worstPrices, 5)) * 100,
    p99Drawdown: (1 - p(worstPrices, 1)) * 100,
    minHFP50: p(minHFs, 50) / 1e18,
    minHFP95: p(minHFs, 5) / 1e18,
    minHFP99: p(minHFs, 1) / 1e18,
    totalPrincipal,
    worstPriceP99: p(worstPrices, 1),
    runResults,
  };
}
