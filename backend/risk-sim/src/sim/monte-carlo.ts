/**
 * Monte Carlo simulation runner
 * Stress tests portfolio under price paths
 */

import { LIQUIDATION, PRECISION, BPS } from "../config/protocol.js";
import type { Borrower } from "../models/portfolio.js";
import type { MarketParams } from "../models/market-shock.js";
import { simulatePricePath } from "../models/market-shock.js";
import type { RNG } from "../models/distributions.js";

const PRICE_SCALE = 1e6;
const COLLATERAL_DECIMALS = 1e18;

export interface LiquidationOverrides {
  thresholdBps: number;
  closeFactorBps: number;
  bonusBps: number;
}

const DEFAULT_OVERRIDES: LiquidationOverrides = {
  thresholdBps: LIQUIDATION.thresholdBps,
  closeFactorBps: LIQUIDATION.closeFactorBps,
  bonusBps: LIQUIDATION.bonusBps,
};

/** Safe bigint-based HF for precision */
function computeHealthFactorSafe(
  collateralAmount: number,
  principalAmount: number,
  priceMultiplier: number,
  thresholdBps: number
): number {
  const coll = BigInt(Math.round(collateralAmount));
  const princ = BigInt(Math.round(principalAmount));
  const price = Math.round(PRICE_SCALE * priceMultiplier);
  if (princ === 0n) return Number.MAX_SAFE_INTEGER;
  const collateralValueUSDC = (coll * BigInt(price)) / BigInt(COLLATERAL_DECIMALS);
  const hf = (collateralValueUSDC * BigInt(thresholdBps) * BigInt(PRECISION)) / (BigInt(BPS) * princ);
  return Number(hf);
}

export interface RunResult {
  /** Whether position was liquidated this run */
  liquidations: number;
  /** Total principal liquidated (USDC 6 decimals) */
  principalLiquidated: number;
  /** Total collateral seized (18 decimals) */
  collateralSeized: number;
  /** Min health factor seen (scaled 1e18) */
  minHealthFactor: number;
  /** Worst price in path (multiplier from 1.0) */
  worstPriceMultiplier: number;
}

function computeLiquidatableAmount(
  collateralAmount: number,
  principalAmount: number,
  priceMultiplier: number,
  overrides: LiquidationOverrides
): { repayAmount: number; collateralSeized: number } | null {
  const price = PRICE_SCALE * priceMultiplier;
  const collateralValueUSDC = (collateralAmount * price) / COLLATERAL_DECIMALS;
  const hf = (collateralValueUSDC * overrides.thresholdBps * PRECISION) / (BPS * principalAmount);
  if (hf >= LIQUIDATION.minHealthFactor) return null;

  const maxRepay = (principalAmount * overrides.closeFactorBps) / BPS;
  const repayAmount = maxRepay;
  const collateralToSeize =
    (repayAmount * COLLATERAL_DECIMALS * (BPS + overrides.bonusBps)) / (price * BPS);
  const seized = Math.min(collateralToSeize, collateralAmount);
  return { repayAmount, collateralSeized: seized };
}

export interface SimConfig {
  /** Market params */
  market: MarketParams;
  /** Number of periods (e.g. 90 days) */
  periods: number;
  /** Override liquidation params for sensitivity/recommendation runs */
  liquidationOverrides?: LiquidationOverrides;
}

export const DEFAULT_SIM_CONFIG: SimConfig = {
  market: {
    drift: -0.02,
    volatility: 0.40,
    jumpProbability: 0.05,
    jumpMean: -0.25,
    jumpVol: 0.15,
    periodsPerYear: 365,
  },
  periods: 90,
};

/**
 * Run single Monte Carlo path
 */
export function runPath(
  rng: RNG,
  borrowers: Borrower[],
  config: SimConfig
): RunResult {
  const overrides = config.liquidationOverrides ?? DEFAULT_OVERRIDES;
  const path = simulatePricePath(rng, config.market, config.periods);
  const worstMultiplier = Math.min(...path);

  let liquidations = 0;
  let principalLiquidated = 0;
  let collateralSeized = 0;
  let minHF = Number.MAX_SAFE_INTEGER;

  for (const b of borrowers) {
    const hfAtWorst = computeHealthFactorSafe(
      b.collateralAmount,
      b.principalAmount,
      worstMultiplier,
      overrides.thresholdBps
    );
    minHF = Math.min(minHF, hfAtWorst);

    const liq = computeLiquidatableAmount(
      b.collateralAmount,
      b.principalAmount,
      worstMultiplier,
      overrides
    );
    if (liq) {
      liquidations++;
      principalLiquidated += liq.repayAmount;
      collateralSeized += liq.collateralSeized;
    }
  }

  return {
    liquidations,
    principalLiquidated,
    collateralSeized,
    minHealthFactor: minHF === Number.MAX_SAFE_INTEGER ? PRECISION : minHF,
    worstPriceMultiplier: worstMultiplier,
  };
}
