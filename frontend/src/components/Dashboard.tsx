"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { contractAddresses } from "@/lib/contracts";
import { creditRegistryAbi } from "@/abi/creditRegistry";
import { loanEngineAbi } from "@/abi/loanEngine";
import { priceRouterAbi } from "@/abi/priceRouter";
import { collateralManagerAbi } from "@/abi/collateralManager";
import { formatUnits } from "viem";

function formatUSDC6(value: bigint) {
  return formatUnits(value, 6);
}

function formatPriceUSD8(value: bigint) {
  return Number(formatUnits(value, 8)).toFixed(2);
}

function isZeroAddress(addr: `0x${string}`) {
  return addr === "0x0000000000000000000000000000000000000000";
}

export function Dashboard() {
  const { address } = useAccount();

  const creditRegistryAddr = contractAddresses.creditRegistry;
  const loanEngineAddr = contractAddresses.loanEngine;
  const priceRouterAddr = contractAddresses.priceRouter;
  const collateralManagerAddr = contractAddresses.collateralManager;
  const wethAddr = contractAddresses.weth;
  const wbtcAddr = contractAddresses.wbtc;

  const hasAddresses =
    !isZeroAddress(creditRegistryAddr) &&
    !isZeroAddress(loanEngineAddr) &&
    !isZeroAddress(priceRouterAddr) &&
    !isZeroAddress(collateralManagerAddr);

  const { data: profile, isLoading: profileLoading } = useReadContract({
    address: hasAddresses ? creditRegistryAddr : undefined,
    abi: creditRegistryAbi,
    functionName: "getCreditProfile",
    args: address ? [address] : undefined,
  });

  const { data: position, isLoading: positionLoading } = useReadContract({
    address: hasAddresses ? loanEngineAddr : undefined,
    abi: loanEngineAbi,
    functionName: "getPosition",
    args: address ? [address] : undefined,
  });

  const collateralAsset = position?.collateralAsset;
  const hasCollateralAsset =
    collateralAsset && collateralAsset !== "0x0000000000000000000000000000000000000000";

  const { data: priceData, isLoading: priceLoading } = useReadContract({
    address: hasAddresses && hasCollateralAsset ? priceRouterAddr : undefined,
    abi: priceRouterAbi,
    functionName: "getPriceUSD8",
    args: collateralAsset ? [collateralAsset as `0x${string}`] : undefined,
  });

  const { data: maxBorrow, isLoading: maxBorrowLoading } = useReadContract({
    address: hasAddresses ? loanEngineAddr : undefined,
    abi: loanEngineAbi,
    functionName: "getMaxBorrow",
    args: address && wethAddr ? [address, wethAddr] : undefined,
  });

  const configCalls = [
    !isZeroAddress(wethAddr) && {
      address: collateralManagerAddr,
      abi: collateralManagerAbi,
      functionName: "getConfig" as const,
      args: [wethAddr] as const,
    },
    !isZeroAddress(wbtcAddr) && {
      address: collateralManagerAddr,
      abi: collateralManagerAbi,
      functionName: "getConfig" as const,
      args: [wbtcAddr] as const,
    },
  ].filter(Boolean) as readonly {
    address: `0x${string}`;
    abi: typeof collateralManagerAbi;
    functionName: "getConfig";
    args: readonly [`0x${string}`];
  }[];

  const { data: configs } = useReadContracts({
    contracts: configCalls,
  });

  const wethConfig = !isZeroAddress(wethAddr)
    ? (configs?.[0] as { result?: { enabled?: boolean; ltvBpsCap?: number; liquidationThresholdBpsCap?: number; haircutBps?: number; debtCeilingUSDC6?: bigint } } | undefined)?.result
    : undefined;

  if (!address) {
    return (
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        <p className="text-neutral-500">Connect a wallet to view your dashboard.</p>
      </div>
    );
  }

  if (!hasAddresses) {
    return (
      <div className="rounded-xl border border-amber-900/50 bg-amber-950/20 p-6">
        <p className="text-amber-600">
          Contract addresses not configured. Set NEXT_PUBLIC_*_ADDRESS in .env.local.
        </p>
        <p className="mt-2 text-sm text-neutral-500">
          See .env.example for required variables.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Credit Profile */}
      <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        <h2 className="mb-4 text-lg font-semibold">Credit Profile</h2>
        {profileLoading ? (
          <p className="text-neutral-500">Loading…</p>
        ) : profile ? (
          <div className="grid gap-2 font-mono text-sm">
            <p>
              <span className="text-neutral-500">Score:</span>{" "}
              {Number(profile.score)} / 1000
            </p>
            <p>
              <span className="text-neutral-500">Risk Tier:</span>{" "}
              {Number(profile.riskTier)}
            </p>
            <p>
              <span className="text-neutral-500">Last Updated:</span>{" "}
              {profile.lastUpdated > BigInt(0)
                ? new Date(Number(profile.lastUpdated) * 1000).toISOString()
                : "—"}
            </p>
          </div>
        ) : (
          <p className="text-neutral-500">No profile onchain.</p>
        )}
      </section>

      {/* Position Summary */}
      <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        <h2 className="mb-4 text-lg font-semibold">Active Position</h2>
        {positionLoading ? (
          <p className="text-neutral-500">Loading…</p>
        ) : position && position.collateralAmount > BigInt(0) ? (
          <div className="grid gap-2 font-mono text-sm">
            <p>
              <span className="text-neutral-500">Collateral Asset:</span>{" "}
              {position.collateralAsset}
            </p>
            <p>
              <span className="text-neutral-500">Collateral Amount:</span>{" "}
              {formatUnits(position.collateralAmount, 18)}
            </p>
            <p>
              <span className="text-neutral-500">Debt (USDC):</span>{" "}
              {formatUSDC6(position.principalAmount)}
            </p>
            <p>
              <span className="text-neutral-500">LTV (bps):</span>{" "}
              {Number(position.ltvBps)}
            </p>
            <p>
              <span className="text-neutral-500">APR (bps):</span>{" "}
              {Number(position.interestRateBps)}%
            </p>
          </div>
        ) : (
          <p className="text-neutral-500">No active loan.</p>
        )}
      </section>

      {/* Price & Staleness */}
      {hasCollateralAsset && (
        <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          <h2 className="mb-4 text-lg font-semibold">Price (Position Asset)</h2>
          {priceLoading ? (
            <p className="text-neutral-500">Loading…</p>
          ) : priceData ? (
            <div className="grid gap-2 font-mono text-sm">
              <p>
                <span className="text-neutral-500">USD Price (8 decimals):</span>{" "}
                {formatPriceUSD8(priceData[0])}
              </p>
              <p>
                <span className="text-neutral-500">Updated At:</span>{" "}
                {priceData[1] > BigInt(0)
                  ? new Date(Number(priceData[1]) * 1000).toISOString()
                  : "—"}
              </p>
              {priceData[2] && (
                <p className="text-amber-500">⚠ Price is stale</p>
              )}
            </div>
          ) : (
            <p className="text-neutral-500">No price available.</p>
          )}
        </section>
      )}

      {/* Max Borrow (WETH) */}
      {!isZeroAddress(wethAddr) && (
        <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          <h2 className="mb-4 text-lg font-semibold">Max Borrow (WETH)</h2>
          {maxBorrowLoading ? (
            <p className="text-neutral-500">Loading…</p>
          ) : maxBorrow !== undefined ? (
            <p className="font-mono text-sm">
              <span className="text-neutral-500">Max borrow (USDC):</span>{" "}
              {formatUSDC6(maxBorrow)}
            </p>
          ) : (
            <p className="text-neutral-500">No collateral or asset not configured.</p>
          )}
        </section>
      )}

      {/* Collateral Config (WETH) */}
      {!isZeroAddress(wethAddr) && wethConfig?.enabled && (
        <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          <h2 className="mb-4 text-lg font-semibold">Collateral Config (WETH)</h2>
          <div className="grid gap-2 font-mono text-sm">
            <p>
              <span className="text-neutral-500">LTV Cap (bps):</span>{" "}
              {wethConfig.ltvBpsCap ?? "—"}
            </p>
            <p>
              <span className="text-neutral-500">Liq Threshold Cap (bps):</span>{" "}
              {wethConfig.liquidationThresholdBpsCap ?? "—"}
            </p>
            <p>
              <span className="text-neutral-500">Haircut (bps):</span>{" "}
              {wethConfig.haircutBps ?? "—"}
            </p>
            <p>
              <span className="text-neutral-500">Debt Ceiling (USDC6):</span>{" "}
              {wethConfig.debtCeilingUSDC6?.toString() ?? "—"}
            </p>
          </div>
        </section>
      )}
    </div>
  );
}
