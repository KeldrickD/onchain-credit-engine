"use client";

import Link from "next/link";
import { dealTypeToLabel, formatRequestedUSDC6, collateralAssetLabel } from "@/lib/deals";
import { SubjectKeyBadge } from "./SubjectKeyBadge";
import { contractAddresses } from "@/lib/contracts";

export type DealCardDeal = {
  dealId: `0x${string}`;
  sponsor: `0x${string}`;
  dealType: `0x${string}`;
  metadataURI: string;
  collateralAsset: `0x${string}`;
  requestedUSDC6: bigint;
  createdAt: bigint;
  active: boolean;
};

type DealCardProps = {
  deal: DealCardDeal;
  committedScore?: number | null;
  committedTier?: number | null;
  committedConfidenceBps?: number | null;
};

export function DealCard({
  deal,
  committedScore,
  committedTier,
  committedConfidenceBps,
}: DealCardProps) {
  const typeLabel = dealTypeToLabel(deal.dealType);
  const collateralLabel = collateralAssetLabel(deal.collateralAsset, {
    weth: contractAddresses.weth,
    wbtc: contractAddresses.wbtc,
  });
  const hasProfile = committedScore != null || committedTier != null;

  return (
    <Link
      href={`/deals/${deal.dealId}`}
      className="block rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 transition hover:border-neutral-700 hover:bg-neutral-900"
    >
      <div className="flex items-start justify-between gap-2">
        <div>
          <span className="font-medium text-neutral-200">{typeLabel}</span>
          <span
            className={`ml-2 rounded px-2 py-0.5 text-xs ${
              deal.active ? "bg-emerald-900/40 text-emerald-400" : "bg-neutral-700 text-neutral-400"
            }`}
          >
            {deal.active ? "Active" : "Inactive"}
          </span>
        </div>
        <SubjectKeyBadge subjectKey={deal.dealId} />
      </div>
      <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-neutral-500">
        <span>Requested: ${formatRequestedUSDC6(deal.requestedUSDC6)} USDC</span>
        <span>Collateral: {collateralLabel}</span>
      </div>
      {hasProfile && (
        <div className="mt-2 text-xs text-neutral-400">
          Committed: score {committedScore ?? "—"} · tier {committedTier ?? "—"}
          {committedConfidenceBps != null && ` · ${(committedConfidenceBps / 100).toFixed(1)}% conf`}
        </div>
      )}
      <p className="mt-2 text-sm text-emerald-500">Open →</p>
    </Link>
  );
}
