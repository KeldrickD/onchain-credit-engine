#!/usr/bin/env node
/**
 * Monitor CLI - scans logs, builds snapshot, exports incidents on anomaly
 *
 * Usage:
 *   pnpm monitor -- --rpc $BASE_SEPOLIA_RPC_URL --lookback 5000 --step 1000
 */

import { Command } from "commander";
import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createPublicClient, http } from "viem";
import { fetchLogsChunked } from "./fetcher.js";
import { buildSnapshot } from "./snapshot.js";
import { writeIncidentExport } from "./incident.js";
import type { MonitorConfig } from "./types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadConfig(): MonitorConfig {
  const path = join(__dirname, "../config.json");
  if (!existsSync(path)) {
    throw new Error("config.json not found. Create backend/monitor/config.json with contract addresses.");
  }
  const raw = readFileSync(path, "utf-8");
  const data = JSON.parse(raw);
  const baseSepolia = data.baseSepolia ?? data;
  return {
    chainId: baseSepolia.chainId ?? 84532,
    network: baseSepolia.network ?? "base-sepolia",
    contracts: {
      loanEngine: process.env.LOAN_ENGINE ?? baseSepolia.contracts?.loanEngine ?? "",
      vault: process.env.TREASURY_VAULT ?? baseSepolia.contracts?.vault ?? "",
      priceOracle: process.env.PRICE_ORACLE ?? baseSepolia.contracts?.priceOracle ?? "",
      registry: process.env.CREDIT_REGISTRY ?? baseSepolia.contracts?.registry ?? "",
      liqManager: process.env.LIQUIDATION_MANAGER ?? baseSepolia.contracts?.liqManager ?? "",
    },
  };
}

const program = new Command();

program
  .name("monitor")
  .description("Scan protocol logs, build snapshot, export incidents on anomaly")
  .requiredOption("--rpc <url>", "RPC URL (e.g. $BASE_SEPOLIA_RPC_URL)")
  .option("--lookback <blocks>", "Blocks to scan backwards from latest", "5000")
  .option("--step <blocks>", "Max log range per request", "1000")
  .option("--out-dir <path>", "Output directory for snapshots/incidents", ".")
  .action(async (opts) => {
    const rpcUrl = opts.rpc as string;
    const lookback = parseInt(opts.lookback, 10);
    const step = parseInt(opts.step, 10);

    const config = loadConfig();

    const addresses: Record<string, string> = {
      priceOracle: config.contracts.priceOracle,
      registry: config.contracts.registry,
      loanEngine: config.contracts.loanEngine,
      liqManager: config.contracts.liqManager,
      vault: config.contracts.vault,
    };

    const nonEmpty = Object.entries(addresses).filter(([, v]) => v && v.length > 0);
    if (nonEmpty.length === 0) {
      console.warn(
        "Warning: No contract addresses configured. Set addresses in config.json or env (LOAN_ENGINE, TREASURY_VAULT, PRICE_ORACLE, CREDIT_REGISTRY, LIQUIDATION_MANAGER)."
      );
      console.warn("Fetching all logs will fail; using placeholder to demonstrate flow.");
    }

    const client = createPublicClient({ transport: http(rpcUrl) });
    const latestBlock = await client.getBlockNumber();
    const toBlock = Number(latestBlock);
    const fromBlock = Math.max(0, toBlock - lookback);

    console.log(`Scanning blocks ${fromBlock} to ${toBlock} (step=${step})...`);

    const logs = await fetchLogsChunked({
      rpcUrl,
      fromBlock: BigInt(fromBlock),
      toBlock: BigInt(toBlock),
      step: BigInt(step),
      addresses: addresses as Record<string, `0x${string}`>,
    });

    console.log(`Fetched ${logs.length} logs`);

    const snapshot = await buildSnapshot(logs, config, fromBlock, toBlock, rpcUrl);

    const outDir = opts.outDir.startsWith("/") || /^[A-Za-z]:/.test(opts.outDir)
      ? opts.outDir
      : join(process.cwd(), opts.outDir);
    const snapDir = join(outDir, "monitor_snapshots");
    if (!existsSync(snapDir)) mkdirSync(snapDir, { recursive: true });
    const snapPath = join(snapDir, "latest.json");
    writeFileSync(snapPath, JSON.stringify(snapshot, null, 2), "utf-8");
    console.log(`Snapshot: ${snapPath}`);

    if (snapshot.anomalies.length > 0) {
      const incidentPath = writeIncidentExport(snapshot, snapshot.anomalies, outDir);
      console.log(`Incident(s) triggered: ${snapshot.anomalies.join("; ")}`);
      console.log(`Incident export: ${incidentPath}`);
    } else {
      console.log("No anomalies detected.");
    }
  });

program.parse();
