/**
 * OCX protocol parameters (mirrors onchain constants)
 * Source: docs/liquidation-model.md, docs/loan-model.md
 */

export const BPS = 10_000;
export const PRECISION = 1e18;
export const USDC_DECIMALS = 6;
export const COLLATERAL_DECIMALS = 18;
export const PRICE_SCALE = 1_000_000; // 1.0 USDC = 1_000_000

/** Score → Terms curve (v0) */
export interface ScoreBand {
  minScore: number;
  ltvBps: number;
  interestRateBps: number;
}

export const SCORE_BANDS: ScoreBand[] = [
  { minScore: 851, ltvBps: 8500, interestRateBps: 500 },
  { minScore: 700, ltvBps: 7500, interestRateBps: 700 },
  { minScore: 400, ltvBps: 6500, interestRateBps: 1000 },
  { minScore: 0, ltvBps: 5000, interestRateBps: 1500 },
];

/** Liquidation parameters (v0) */
export const LIQUIDATION = {
  thresholdBps: 8800,
  closeFactorBps: 5000,
  bonusBps: 800,
  minHealthFactor: 1e18,
} as const;

export function getTermsForScore(score: number): { ltvBps: number; interestRateBps: number } {
  for (const band of SCORE_BANDS) {
    if (score >= band.minScore) {
      return { ltvBps: band.ltvBps, interestRateBps: band.interestRateBps };
    }
  }
  return { ltvBps: 5000, interestRateBps: 1500 };
}
