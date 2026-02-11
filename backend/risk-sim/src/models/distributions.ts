/**
 * Distribution sampling for Monte Carlo simulation
 * Uses seeded RNG for reproducibility
 */

export interface RNG {
  (): number;
}

/** Uniform [0,1) */
export function uniform(rng: RNG): number {
  return rng();
}

/** Normal (Box-Muller) */
export function normal(rng: RNG, mu = 0, sigma = 1): number {
  const u1 = rng();
  const u2 = rng();
  if (u1 <= 1e-10) return normal(rng, mu, sigma);
  return mu + sigma * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

/** Log-normal (price returns) */
export function logNormal(rng: RNG, mu: number, sigma: number): number {
  return Math.exp(normal(rng, mu, sigma));
}

/** Exponential (e.g. default timing) */
export function exponential(rng: RNG, lambda: number): number {
  const u = rng();
  if (u >= 1) return 0;
  return -Math.log(1 - u) / lambda;
}

/** Sample from discrete weights (e.g. score distribution) */
export function weighted(rng: RNG, weights: number[]): number {
  const total = weights.reduce((a, b) => a + b, 0);
  let r = rng() * total;
  for (let i = 0; i < weights.length; i++) {
    r -= weights[i];
    if (r <= 0) return i;
  }
  return weights.length - 1;
}
