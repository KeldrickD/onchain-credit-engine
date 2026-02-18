"use client";

import { dealTypeToLabel, formatRequestedUSDC6, collateralAssetLabel } from "@/lib/deals";
import { SubjectKeyBadge } from "./SubjectKeyBadge";
import { contractAddresses } from "@/lib/contracts";

export type DealHeaderDeal = {
  dealId: `0x${string}`;
  sponsor: `0x${string}`;
  dealType: `0x${string}`;
  metadataURI: string;
  collateralAsset: `0x${string}`;
  requestedUSDC6: bigint;
  createdAt: bigint;
  active: boolean;
};

type DealHeaderProps = {
  deal: DealHeaderDeal;
};

export function DealHeader({ deal }: DealHeaderProps) {
  const typeLabel = dealTypeToLabel(deal.dealType);
  const collateralLabel = collateralAssetLabel(deal.collateralAsset, {
    weth: contractAddresses.weth,
    wbtc: contractAddresses.wbtc,
  });

  return (
    <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xl font-semibold text-neutral-100">{typeLabel}</span>
        <span
          className={`rounded px-2 py-0.5 text-xs ${
            deal.active ? "bg-emerald-900/40 text-emerald-400" : "bg-neutral-700 text-neutral-400"
          }`}
        >
          {deal.active ? "Active" : "Inactive"}
        </span>
        <SubjectKeyBadge subjectKey={deal.dealId} className="ml-auto" />
      </div>
      <div className="mt-2 flex flex-wrap gap-x-6 gap-y-1 text-sm text-neutral-500">
        <span>Requested: ${formatRequestedUSDC6(deal.requestedUSDC6)} USDC</span>
        <span>Collateral: {collateralLabel}</span>
      </div>
      <p className="mt-1 font-mono text-xs text-neutral-500">
        Sponsor: {deal.sponsor.slice(0, 10)}…{deal.sponsor.slice(-8)}
      </p>
    </div>
  );
}
