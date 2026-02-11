/**
 * Report generation - JSON + Markdown
 */

import type { SimulationResult } from "../sim/runner.js";
import type { Recommendations } from "../sim/recommend.js";
import { LIQUIDATION, SCORE_BANDS } from "../config/protocol.js";
import type { MarketParams } from "../models/market-shock.js";
import type { PortfolioParams } from "../models/portfolio.js";

export interface ReportJson {
  meta: {
    timestamp: string;
    runs: number;
    seed: number;
    borrowerCount: number;
    periods: number;
  };
  protocolSnapshot: {
    liquidationThresholdBps: number;
    closeFactorBps: number;
    bonusBps: number;
    scoreBands: Array<{ minScore: number; ltvBps: number; interestRateBps: number }>;
  };
  marketParams: MarketParams;
  portfolioParams: PortfolioParams;
  results: {
    liquidationFrequency: number;
    avgLiquidationsPerRun: number;
    expectedLossPct: number;
    p95Drawdown: number;
    p99Drawdown: number;
    minHFP50: number;
    minHFP95: number;
    minHFP99: number;
    totalPrincipal: number;
    worstPriceP99: number;
  };
  recommendations?: Recommendations;
}

export function toJson(result: SimulationResult, recommendations?: Recommendations): ReportJson {
  const json: ReportJson = {
    meta: {
      timestamp: new Date().toISOString(),
      runs: result.runs,
      seed: result.seed,
      borrowerCount: result.borrowerCount,
      periods: result.periods,
    },
    protocolSnapshot: {
      liquidationThresholdBps: LIQUIDATION.thresholdBps,
      closeFactorBps: LIQUIDATION.closeFactorBps,
      bonusBps: LIQUIDATION.bonusBps,
      scoreBands: SCORE_BANDS.map((b) => ({
        minScore: b.minScore,
        ltvBps: b.ltvBps,
        interestRateBps: b.interestRateBps,
      })),
    },
    marketParams: {
      drift: -0.02,
      volatility: 0.40,
      jumpProbability: 0.05,
      jumpMean: -0.25,
      jumpVol: 0.15,
      periodsPerYear: 365,
    },
    portfolioParams: {
      borrowerCount: 100,
      collateralMean: 50 * 1e18,
      collateralStd: 30 * 1e18,
      scoreWeights: [0.15, 0.25, 0.35, 0.25],
      utilizationMean: 0.75,
      utilizationStd: 0.15,
    },
    results: {
      liquidationFrequency: result.liquidationFrequency,
      avgLiquidationsPerRun: result.avgLiquidationsPerRun,
      expectedLossPct: result.expectedLossPct,
      p95Drawdown: result.p95Drawdown,
      p99Drawdown: result.p99Drawdown,
      minHFP50: result.minHFP50,
      minHFP95: result.minHFP95,
      minHFP99: result.minHFP99,
      totalPrincipal: result.totalPrincipal,
      worstPriceP99: result.worstPriceP99,
    },
  };
  if (recommendations) {
    json.recommendations = recommendations;
  }
  return json;
}

export function toMarkdown(
  result: SimulationResult,
  recommendations?: Recommendations
): string {
  const pct = (n: number) => (n * 100).toFixed(2) + "%";
  const fmt = (n: number, d = 2) => n.toFixed(d);

  return `# OCX Risk Simulation Report

**Generated:** ${new Date().toISOString()}

## Configuration

| Parameter | Value |
|-----------|-------|
| Monte Carlo runs | ${result.runs} |
| Seed | ${result.seed} |
| Borrowers | ${result.borrowerCount} |
| Periods | ${result.periods} (days) |
| Total portfolio principal | ${(result.totalPrincipal / 1e6).toLocaleString()} USDC |

## Protocol Snapshot

| Parameter | Value |
|-----------|-------|
| Liquidation threshold | ${LIQUIDATION.thresholdBps / 100}% |
| Close factor | ${LIQUIDATION.closeFactorBps / 100}% |
| Liquidation bonus | ${LIQUIDATION.bonusBps / 100}% |

## Simulation Assumptions

- **Drift:** -2% annual (bearish stress)
- **Volatility:** 40% annualized
- **Jump probability:** 5% per period
- **Jump magnitude:** -25% mean, 15% vol

## Results

| Metric | Value |
|--------|-------|
| Liquidation frequency | ${pct(result.liquidationFrequency)} of runs |
| Avg liquidations per run (when any) | ${fmt(result.avgLiquidationsPerRun, 2)} |
| Expected loss (EL) | ${fmt(result.expectedLossPct, 2)}% of principal |
| 95th percentile drawdown | ${fmt(result.p95Drawdown, 1)}% |
| 99th percentile drawdown | ${fmt(result.p99Drawdown, 1)}% |
| Min HF (median) | ${fmt(result.minHFP50, 3)} |
| Min HF (5th pctl) | ${fmt(result.minHFP95, 3)} |
| Min HF (1st pctl) | ${fmt(result.minHFP99, 3)} |
| Worst price (1st pctl) | ${fmt(result.worstPriceP99 * 100, 1)}% of initial |

## Summary

- **Runs with ≥1 liquidation:** ${Math.round(result.liquidationFrequency * result.runs)}
- **Tail risk:** In 1% of scenarios, min HF drops to ${fmt(result.minHFP99, 2)} and price to ${fmt(result.worstPriceP99 * 100, 1)}% of initial.
${
  recommendations
    ? `

## Parameter Recommendations

### Targets

| Metric | Target |
|--------|--------|
| Max liquidation frequency | ${(recommendations.target.maxLiquidationFrequency * 100).toFixed(0)}% |
| Max expected loss | ${recommendations.target.maxExpectedLossPct}% |
| Max 95th percentile drawdown | ${recommendations.target.maxP95DrawdownPct}% |

### Current vs Proposed

| Parameter | Current | Proposed |
|-----------|---------|----------|
| Liquidation threshold | ${recommendations.current.liquidationThresholdBps / 100}% | ${recommendations.proposed.liquidationThresholdBps / 100}% |
| Close factor | ${recommendations.current.closeFactorBps / 100}% | ${recommendations.proposed.closeFactorBps / 100}% |
| Liquidation bonus | ${recommendations.current.bonusBps / 100}% | ${recommendations.proposed.bonusBps / 100}% |

### Rationale

${recommendations.rationale.map((r) => `- ${r}`).join("\n")}

### Sensitivity Summary (threshold sweep)

| Threshold (bps) | Liq Freq | EL (%) |
|-----------------|----------|--------|
${recommendations.sensitivity.summary
  .map((s) => `| ${s.thresholdBps} | ${s.liqFreq.toFixed(2)} | ${s.EL.toFixed(2)} |`)
  .join("\n")}

### Utilization Sensitivity (higher leverage)

| Utilization | Liq Freq | EL (%) |
|-------------|----------|--------|
${(recommendations.utilizationSensitivity ?? [])
  .map((s) => `| ${s.utilizationMean} | ${s.liqFreq.toFixed(2)} | ${s.EL.toFixed(2)} |`)
  .join("\n")}

### LTV Multiplier Sensitivity

| LTV Mult | Liq Freq | EL (%) |
|----------|----------|--------|
${(recommendations.ltvSensitivity ?? [])
  .map((s) => `| ${s.ltvMultiplier} | ${s.liqFreq.toFixed(2)} | ${s.EL.toFixed(2)} |`)
  .join("\n")}

### Leverage Diagnostics

${recommendations.leverageNotes.map((n) => `- ${n}`).join("\n")}

**Most sensitive inputs:** ${recommendations.mostSensitiveInputs.join(" > ")}

**Suggested next knobs:** ${recommendations.suggestedNextKnobs.join("; ")}
`
    : ""
}
`;
}
