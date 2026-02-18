"use client";

import { useAccount, useReadContracts } from "wagmi";
import { dealFactoryAbi } from "@/abi/dealFactory";
import { creditRegistryAbi } from "@/abi/creditRegistry";
import { contractAddresses } from "@/lib/contracts";
import { getStoredDealIds, addStoredDealId } from "@/lib/deals";
import { DealCard, type DealCardDeal } from "./DealCard";
import { useState, useEffect, useMemo } from "react";

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

function isZero(a: string) {
  return !a || a === ZERO;
}

export function DealList() {
  const { address } = useAccount();
  const [dealIds, setDealIds] = useState<string[]>([]);
  const [addIdInput, setAddIdInput] = useState("");

  useEffect(() => {
    setDealIds(getStoredDealIds());
  }, []);

  const addDealId = () => {
    const id = addIdInput.trim();
    if (!id || id.length !== 66 || !id.startsWith("0x")) return;
    if (dealIds.includes(id)) return;
    addStoredDealId(id);
    setDealIds([...dealIds, id]);
    setAddIdInput("");
  };

  const hasFactory = !isZero(contractAddresses.dealFactory);
  const hasCredit = !isZero(contractAddresses.creditRegistry);

  const dealCalls = useMemo(
    () =>
      dealIds
        .filter((id) => id.startsWith("0x") && id.length === 66)
        .map((id) => ({
          address: contractAddresses.dealFactory,
          abi: dealFactoryAbi,
          functionName: "getDeal" as const,
          args: [id as `0x${string}`],
        })),
    [dealIds]
  );

  const profileCalls = useMemo(
    () =>
      dealIds
        .filter((id) => id.startsWith("0x") && id.length === 66)
        .map((id) => ({
          address: contractAddresses.creditRegistry,
          abi: creditRegistryAbi,
          functionName: "getProfile" as const,
          args: [id as `0x${string}`],
        })),
    [dealIds]
  );

  const { data: dealResults } = useReadContracts({ contracts: hasFactory ? dealCalls : [] });
  const { data: profileResults } = useReadContracts({ contracts: hasCredit ? profileCalls : [] });

  const dealsWithProfiles = useMemo(() => {
    const list: Array<{ deal: DealCardDeal; score?: number; tier?: number; confidenceBps?: number }> = [];
    if (!dealResults?.length) return list;
    dealResults.forEach((r, i) => {
      if (r.status !== "success" || !r.result) return;
      const d = r.result as unknown as DealCardDeal;
      if (d.sponsor === "0x0000000000000000000000000000000000000000") return;
      const profile = profileResults?.[i]?.status === "success" && profileResults?.[i]?.result
        ? (profileResults[i].result as { score: bigint; riskTier: bigint; confidenceBps: number })
        : null;
      list.push({
        deal: d,
        score: profile ? Number(profile.score) : undefined,
        tier: profile ? Number(profile.riskTier) : undefined,
        confidenceBps: profile?.confidenceBps,
      });
    });
    return list;
  }, [dealResults, profileResults]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <label className="text-sm text-neutral-500">Add deal by ID (0x + 64 hex)</label>
        <input
          type="text"
          value={addIdInput}
          onChange={(e) => setAddIdInput(e.target.value)}
          placeholder="0x..."
          className="rounded-lg border border-neutral-700 bg-neutral-800 px-3 py-1.5 font-mono text-sm w-72"
        />
        <button
          type="button"
          onClick={addDealId}
          className="rounded-lg bg-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-600"
        >
          Add
        </button>
      </div>

      {!hasFactory && (
        <p className="text-amber-600 text-sm">DealFactory not configured. Set NEXT_PUBLIC_DEAL_FACTORY_ADDRESS.</p>
      )}

      {dealsWithProfiles.length === 0 && hasFactory && (
        <p className="text-neutral-500">
          No deals in list. Create one at <a href="/deals/create" className="text-emerald-500 hover:underline">/deals/create</a> or add a deal ID above.
        </p>
      )}

      <ul className="space-y-3">
        {dealsWithProfiles.map(({ deal, score, tier, confidenceBps }) => (
          <li key={deal.dealId}>
            <DealCard
              deal={deal}
              committedScore={score}
              committedTier={tier}
              committedConfidenceBps={confidenceBps}
            />
          </li>
        ))}
      </ul>
    </div>
  );
}
