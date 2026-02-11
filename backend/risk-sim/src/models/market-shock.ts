/**
 * Market shock model for stress testing
 * Geometric Brownian Motion + jump diffusion
 */

import type { RNG } from "./distributions.js";
import { normal } from "./distributions.js";

export interface MarketParams {
  /** Annual drift (e.g. 0 = flat, -0.1 = -10% drift) */
  drift: number;
  /** Annual volatility (e.g. 0.3 = 30%) */
  volatility: number;
  /** Probability of jump per period */
  jumpProbability: number;
  /** Jump mean (e.g. -0.2 = -20% on jump) */
  jumpMean: number;
  /** Jump volatility */
  jumpVol: number;
  /** Periods per year (e.g. 365 for daily, 52 for weekly) */
  periodsPerYear: number;
}

export const DEFAULT_MARKET: MarketParams = {
  drift: -0.02,
  volatility: 0.40,
  jumpProbability: 0.05,
  jumpMean: -0.25,
  jumpVol: 0.15,
  periodsPerYear: 365,
};

/**
 * Simulate price path for N periods
 * Returns array of price multipliers (1.0 = no change)
 */
export function simulatePricePath(
  rng: RNG,
  params: MarketParams,
  periods: number
): number[] {
  const dt = 1 / params.periodsPerYear;
  const mu = params.drift * dt;
  const sigma = params.volatility * Math.sqrt(dt);

  const path: number[] = [1.0];
  for (let i = 1; i < periods; i++) {
    let ret = mu + sigma * normal(rng);
    if (rng() < params.jumpProbability) {
      ret += normal(rng, params.jumpMean, params.jumpVol);
    }
    path.push(path[i - 1]! * Math.exp(ret));
  }
  return path;
}
