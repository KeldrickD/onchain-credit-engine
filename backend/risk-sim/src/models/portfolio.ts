/**
 * Portfolio definition for simulation
 */

import { getTermsForScore } from "../config/protocol.js";
import type { RNG } from "./distributions.js";
import { normal, weighted } from "./distributions.js";

export interface Borrower {
  id: number;
  collateralAmount: number;
  score: number;
  ltvBps: number;
  principalAmount: number;
}

export interface PortfolioParams {
  /** Number of borrowers */
  borrowerCount: number;
  /** Collateral amount: mean, std (18 decimals) */
  collateralMean: number;
  collateralStd: number;
  /** Score distribution weights [0-399, 400-699, 700-850, 851-1000] */
  scoreWeights: number[];
  /** LTV utilization (0-1): fraction of max borrow actually borrowed */
  utilizationMean: number;
  utilizationStd: number;
  /** LTV multiplier (e.g. 0.85 = 15% haircut on all LTV bands) */
  ltvMultiplier?: number;
}

export const DEFAULT_PORTFOLIO: PortfolioParams = {
  borrowerCount: 100,
  collateralMean: 50 * 1e18,
  collateralStd: 30 * 1e18,
  scoreWeights: [0.15, 0.25, 0.35, 0.25],
  utilizationMean: 0.75,
  utilizationStd: 0.15,
};

/** Score band midpoints for sampling */
const SCORE_MIDPOINTS = [200, 550, 775, 925];

export function generatePortfolio(rng: () => number, params: PortfolioParams): Borrower[] {
  const borrowers: Borrower[] = [];

  for (let i = 0; i < params.borrowerCount; i++) {
    const collateral = Math.max(1e18, normal(rng, params.collateralMean, params.collateralStd));
    const band = weighted(rng, params.scoreWeights);
    const score = SCORE_MIDPOINTS[band] ?? 500;
    const { ltvBps } = getTermsForScore(score);
    const mult = params.ltvMultiplier ?? 1;
    const effectiveLtvBps = Math.max(3000, Math.min(9000, Math.floor(ltvBps * mult)));

    const maxBorrow = (collateral * effectiveLtvBps) / 10_000 / 1e12;
    const utilization = Math.max(0.5, Math.min(1, normal(rng, params.utilizationMean, params.utilizationStd)));
    const principal = maxBorrow * utilization;

    borrowers.push({
      id: i,
      collateralAmount: collateral,
      score,
      ltvBps: effectiveLtvBps,
      principalAmount: principal,
    });
  }

  return borrowers;
}
