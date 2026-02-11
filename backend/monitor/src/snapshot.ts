/**
 * Build monitor snapshot from decoded events
 */

import { createPublicClient, http } from "viem";
import type { Address } from "viem";
import type {
  Snapshot,
  PriceUpdateEvent,
  LiquidationEvent,
  LoanEvent,
  RiskContext,
  MonitorConfig,
} from "./types.js";
import { decodeLog } from "./decoder.js";
import { detectAnomalies } from "./anomaly.js";
import type { RawLog } from "./fetcher.js";
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const MAX_EVENTS_PER_TYPE = 50; // keep last N to avoid huge files

function loadRiskContext(): RiskContext | undefined {
  const path = join(__dirname, "../../risk-sim/reports/latest.json");
  if (!existsSync(path)) return undefined;
  try {
    const raw = readFileSync(path, "utf-8");
    const data = JSON.parse(raw);
    const results = data.results ?? {};
    const rec = data.recommendations ?? {};
    const mostSensitive = rec.mostSensitiveInputs ?? [];
    return {
      latestSim: {
        path: "../risk-sim/reports/latest.json",
        summary: {
          liqFreq: results.liquidationFrequency ?? 0,
          expectedLossPct: results.expectedLossPct ?? 0,
          mostSensitiveInputs: mostSensitive,
        },
      },
    };
  } catch {
    return undefined;
  }
}

export async function buildSnapshot(
  logs: RawLog[],
  config: MonitorConfig,
  fromBlock: number,
  toBlock: number,
  rpcUrl: string
): Promise<Snapshot> {
  const priceUpdates: PriceUpdateEvent[] = [];
  const liquidations: LiquidationEvent[] = [];
  const loans: LoanEvent[] = [];

  let creditProfileUpdates = 0;
  let deposits = 0;
  let withdrawals = 0;

  const client = createPublicClient({ transport: http(rpcUrl) });

  // Fetch block timestamps only for blocks we need (price staleness + anomaly windows)
  const blockTimestamps = new Map<number, number>();
  const blocksToFetch = new Set<number>();
  for (const log of logs) {
    blocksToFetch.add(Number(log.blockNumber));
  }
  // Limit to last 500 blocks to avoid excessive RPC calls
  const sorted = [...blocksToFetch].sort((a, b) => b - a).slice(0, 500);
  for (const bn of sorted) {
    try {
      const block = await client.getBlock({ blockNumber: BigInt(bn) });
      if (block?.timestamp) blockTimestamps.set(bn, Number(block.timestamp));
    } catch {
      // ignore
    }
  }

  const nowSeconds = Math.floor(Date.now() / 1000);

  for (const log of logs) {
    const decoded = decodeLog(log);
    if (!decoded) continue;

    if ("asset" in decoded && "price" in decoded && !("liquidator" in decoded)) {
      priceUpdates.push(decoded as PriceUpdateEvent);
    } else if ("liquidator" in decoded && "repayAmount" in decoded) {
      liquidations.push(decoded as LiquidationEvent);
    } else if ("type" in decoded) {
      loans.push(decoded as LoanEvent);
    }
  }

  // Trim to last N events
  const trim = <T>(arr: T[], max: number) =>
    arr.length > max ? arr.slice(-max) : arr;

  const anomalies = detectAnomalies({
    priceUpdates,
    liquidations,
    loans,
    blockTimestamps,
    nowSeconds,
  });

  const loanOpened = loans.filter((l) => l.type === "LoanOpened");
  const repays = loans.filter((l) => l.type === "LoanRepaid");

  const lastPriceUpdate = priceUpdates[priceUpdates.length - 1];
  const lastLoanOpened = loanOpened[loanOpened.length - 1];

  let priceUpdateAt = "";
  if (lastPriceUpdate) {
    const ts = blockTimestamps.get(lastPriceUpdate.blockNumber);
    if (ts) priceUpdateAt = new Date(ts * 1000).toISOString();
  }

  const riskContext = loadRiskContext();

  return {
    meta: {
      chainId: config.chainId,
      network: config.network,
      fromBlock,
      toBlock,
      generatedAt: new Date().toISOString(),
    },
    contracts: {
      loanEngine: config.contracts.loanEngine,
      vault: config.contracts.vault,
      priceOracle: config.contracts.priceOracle,
      registry: config.contracts.registry,
      liqManager: config.contracts.liqManager,
    },
    counts: {
      loanOpened: loanOpened.length,
      liquidations: liquidations.length,
      priceUpdates: priceUpdates.length,
      repays: repays.length,
      creditProfileUpdates,
      deposits,
      withdrawals,
    },
    lastSeen: {
      priceUpdateBlock: lastPriceUpdate?.blockNumber ?? 0,
      priceUpdateAt,
      loanOpenedBlock: lastLoanOpened?.blockNumber ?? 0,
    },
    events: {
      priceUpdates: trim(priceUpdates, MAX_EVENTS_PER_TYPE),
      liquidations: trim(liquidations, MAX_EVENTS_PER_TYPE),
      loans: trim(loans, MAX_EVENTS_PER_TYPE),
    },
    anomalies,
    riskContext,
  };
}
