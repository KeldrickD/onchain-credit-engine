#!/usr/bin/env node
/**
 * OCX Risk Simulation CLI
 * pnpm risk:sim -- --runs 10000 --seed 42
 */

import { Command } from "commander";
import { mkdir, writeFile } from "fs/promises";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

import { runRecommendation } from "./sim/recommend.js";
import { DEFAULT_PORTFOLIO } from "./models/portfolio.js";
import { toJson, toMarkdown } from "./reports/generate.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPORTS_DIR = join(__dirname, "..", "reports");

const program = new Command();

program
  .name("risk:sim")
  .description("OCX Monte Carlo risk simulation")
  .option("-r, --runs <number>", "Number of Monte Carlo runs (per sensitivity point)", "500")
  .option("-s, --seed <number>", "RNG seed for reproducibility", "42")
  .option("-b, --borrowers <number>", "Portfolio size", "100")
  .option("--no-recommend", "Skip parameter recommendation (faster)")
  .action(async (opts) => {
    const runs = parseInt(opts.runs, 10);
    const seed = parseInt(opts.seed, 10);
    const borrowerCount = parseInt(opts.borrowers, 10);
    const doRecommend = opts.recommend !== false;

    const portfolioParams = { ...DEFAULT_PORTFOLIO, borrowerCount };

    let result;
    let recommendations;
    if (doRecommend) {
      console.log(`Running recommendation (${runs} runs × 6 thresholds, seed=${seed})...`);
      const out = runRecommendation(runs, seed, undefined, portfolioParams);
      result = out.result;
      recommendations = out.recommendations;
      console.log(`Proposed: threshold=${recommendations.proposed.liquidationThresholdBps}bps, close=${recommendations.proposed.closeFactorBps}bps, bonus=${recommendations.proposed.bonusBps}bps`);
    } else {
      console.log(`Running ${runs} paths (seed=${seed}, borrowers=${borrowerCount})...`);
      const { runSimulation } = await import("./sim/runner.js");
      const { DEFAULT_SIM_CONFIG } = await import("./sim/monte-carlo.js");
      result = runSimulation(runs, seed, portfolioParams, DEFAULT_SIM_CONFIG);
    }

    const reportJson = toJson(result, recommendations);
    const reportMd = toMarkdown(result, recommendations);

    await mkdir(REPORTS_DIR, { recursive: true });

    const jsonPath = join(REPORTS_DIR, "latest.json");
    const mdPath = join(REPORTS_DIR, "latest.md");

    await writeFile(jsonPath, JSON.stringify(reportJson, null, 2), "utf-8");
    await writeFile(mdPath, reportMd, "utf-8");

    const runId = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const runJsonPath = join(REPORTS_DIR, `run-${runId.replace(/-/g, "").slice(0, 8)}.json`);
    const runMdPath = join(REPORTS_DIR, `run-${runId.replace(/-/g, "").slice(0, 8)}.md`);
    await writeFile(runJsonPath, JSON.stringify(reportJson, null, 2), "utf-8");
    await writeFile(runMdPath, reportMd, "utf-8");

    console.log(`\nReport written:`);
    console.log(`  ${jsonPath}`);
    console.log(`  ${mdPath}`);
    console.log(`  ${runJsonPath}`);
    console.log(`  ${runMdPath}`);
    console.log(`\nLiquidation frequency: ${(result.liquidationFrequency * 100).toFixed(2)}%`);
    console.log(`Expected loss: ${result.expectedLossPct.toFixed(2)}%`);
  });

// Strip standalone "--" so commander parses options correctly
const args = process.argv.slice(2).filter((x) => x !== "--");
program.parse(["node", "cli", ...args]);
