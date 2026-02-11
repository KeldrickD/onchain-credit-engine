/**
 * Incident export - operator-grade artifact when anomaly triggers
 */

import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { IncidentExport, Snapshot } from "./types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

function getRecommendedActions(triggeredRules: string[]): string[] {
  const actions: string[] = [];
  for (const r of triggeredRules) {
    if (r.startsWith("liquidation_burst")) {
      actions.push("Check liquidationManager and price oracle for manipulation");
      actions.push("Review collateral prices and LTV thresholds");
    } else if (r.startsWith("price_feed_spam")) {
      actions.push("Verify oracle signer and rate limits");
      actions.push("Check for potential oracle griefing");
    } else if (r.startsWith("oracle_staleness")) {
      actions.push("Trigger manual price update or verify oracle uptime");
      actions.push("Consider pausing liquidations if price is unreliable");
    } else if (r.startsWith("borrow_surge")) {
      actions.push("Review vault liquidity and utilization");
      actions.push("Consider rate limits or circuit breakers");
    } else if (r.startsWith("repay_spike_after_liquidations")) {
      actions.push("Assess cascade risk; review close factor and bonus");
      actions.push("Check risk-sim recommendations for parameter tweaks");
    }
  }
  return [...new Set(actions)];
}

export function writeIncidentExport(
  snapshot: Snapshot,
  triggeredRules: string[],
  outputDir: string
): string {
  const id = `incident-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const dir = join(outputDir, "incident_exports");
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const incident: IncidentExport = {
    id,
    triggeredRules,
    timeWindow: {
      fromBlock: snapshot.meta.fromBlock,
      toBlock: snapshot.meta.toBlock,
    },
    topTxs: [
      ...new Set([
        ...snapshot.events.priceUpdates.map((e) => e.txHash),
        ...snapshot.events.liquidations.map((e) => e.txHash),
        ...snapshot.events.loans.map((e) => e.txHash),
      ]),
    ].slice(0, 20),
    decodedEvents: [
      ...snapshot.events.liquidations.slice(-10),
      ...snapshot.events.priceUpdates.slice(-5),
      ...snapshot.events.loans.filter((l) => l.type === "LoanRepaid").slice(-10),
    ],
    configSnapshot: snapshot.contracts,
    riskSimSummary: snapshot.riskContext?.latestSim?.summary,
    recommendedActions: getRecommendedActions(triggeredRules),
    notes: `Anomalies detected at ${snapshot.meta.generatedAt}. Chain: ${snapshot.meta.network} blocks ${snapshot.meta.fromBlock}-${snapshot.meta.toBlock}.`,
  };

  const path = join(dir, `${id}.json`);
  writeFileSync(path, JSON.stringify(incident, null, 2), "utf-8");
  return path;
}
