/**
 * Deterministic anomaly rules (v0)
 */

import type { PriceUpdateEvent, LiquidationEvent, LoanEvent } from "./types.js";

export interface AnomalyInputs {
  priceUpdates: PriceUpdateEvent[];
  liquidations: LiquidationEvent[];
  loans: LoanEvent[];
  blockTimestamps: Map<number, number>; // blockNumber -> unix timestamp
  nowSeconds: number;
}

const STALENESS_MINUTES = 10;
const STALENESS_SECONDS = STALENESS_MINUTES * 60;

export function detectAnomalies(inputs: AnomalyInputs): string[] {
  const anomalies: string[] = [];

  // 1. Liquidation burst: liquidations >= 5 within <= 50 blocks
  const liqBlocks = [...new Set(inputs.liquidations.map((l) => l.blockNumber))].sort((a, b) => a - b);
  for (let i = 0; i < liqBlocks.length; i++) {
    const windowStart = liqBlocks[i];
    const windowEnd = windowStart + 50;
    const count = inputs.liquidations.filter(
      (l) => l.blockNumber >= windowStart && l.blockNumber <= windowEnd
    ).length;
    if (count >= 5) {
      anomalies.push(`liquidation_burst: ${count} liquidations within 50 blocks (from block ${windowStart})`);
      break; // one trigger per rule
    }
  }

  // 2. Price feed spam: PriceUpdated >= 10 within <= 200 blocks
  const priceBlocks = inputs.priceUpdates.map((p) => p.blockNumber).sort((a, b) => a - b);
  for (let i = 0; i < priceBlocks.length; i++) {
    const windowStart = priceBlocks[i];
    const windowEnd = windowStart + 200;
    const count = inputs.priceUpdates.filter(
      (p) => p.blockNumber >= windowStart && p.blockNumber <= windowEnd
    ).length;
    if (count >= 10) {
      anomalies.push(`price_feed_spam: ${count} PriceUpdated within 200 blocks (from block ${windowStart})`);
      break;
    }
  }

  // 3. Oracle staleness: latest price update older than 10 minutes
  if (inputs.priceUpdates.length > 0) {
    const latest = inputs.priceUpdates[inputs.priceUpdates.length - 1]!;
    const blockTs = inputs.blockTimestamps.get(latest.blockNumber);
    const priceTs = blockTs ?? 0;
    if (priceTs > 0 && inputs.nowSeconds - priceTs > STALENESS_SECONDS) {
      anomalies.push(
        `oracle_staleness: latest price update at block ${latest.blockNumber} is older than ${STALENESS_MINUTES} minutes`
      );
    }
  }

  // 4. Borrow surge: LoanOpened > 20 within <= 500 blocks
  const loanOpened = inputs.loans.filter((l) => l.type === "LoanOpened");
  for (let i = 0; i < loanOpened.length; i++) {
    const windowStart = loanOpened[i]!.blockNumber;
    const windowEnd = windowStart + 500;
    const count = loanOpened.filter(
      (l) => l.blockNumber >= windowStart && l.blockNumber <= windowEnd
    ).length;
    if (count > 20) {
      anomalies.push(`borrow_surge: ${count} LoanOpened within 500 blocks (from block ${windowStart})`);
      break;
    }
  }

  // 5. Repay spike after liquidations: repays >= 10 within 200 blocks after a liquidation burst
  const repays = inputs.loans.filter((l) => l.type === "LoanRepaid");
  for (let i = 0; i < liqBlocks.length; i++) {
    const burstStart = liqBlocks[i]!;
    const burstEnd = burstStart + 50;
    const count = inputs.liquidations.filter(
      (l) => l.blockNumber >= burstStart && l.blockNumber <= burstEnd
    ).length;
    if (count >= 5) {
      const afterStart = burstEnd + 1;
      const afterEnd = burstEnd + 200;
      const repayCountInWindow = repays.filter(
        (r) => r.blockNumber >= afterStart && r.blockNumber <= afterEnd
      ).length;
      if (repayCountInWindow >= 10) {
        anomalies.push(
          `repay_spike_after_liquidations: ${repayCountInWindow} repays within 200 blocks after liquidation burst (blocks ${afterStart}-${afterEnd})`
        );
        break;
      }
    }
  }

  return anomalies;
}
