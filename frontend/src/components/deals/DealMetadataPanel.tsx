"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import toast from "react-hot-toast";
import { dealFactoryAbi } from "@/abi/dealFactory";
import { subjectRegistryAbi } from "@/abi/subjectRegistry";
import { contractAddresses } from "@/lib/contracts";
import { ValueRow } from "./ValueRow";

export type DealMetadataDeal = {
  dealId: `0x${string}`;
  sponsor: `0x${string}`;
  dealType: `0x${string}`;
  metadataURI: string;
  collateralAsset: `0x${string}`;
  requestedUSDC6: bigint;
  createdAt: bigint;
  active: boolean;
};

type DealMetadataPanelProps = {
  deal: DealMetadataDeal;
  onUpdated?: () => void;
};

const ZERO = "0x0000000000000000000000000000000000000000";

function isZero(a: string) {
  return !a || a === ZERO;
}

export function DealMetadataPanel({ deal, onUpdated }: DealMetadataPanelProps) {
  const { address } = useAccount();
  const [newUri, setNewUri] = useState(deal.metadataURI);
  useEffect(() => {
    setNewUri(deal.metadataURI);
  }, [deal.metadataURI]);

  const { data: isAuthorized } = useReadContract({
    address: contractAddresses.subjectRegistry,
    abi: subjectRegistryAbi,
    functionName: "isAuthorized",
    args: [deal.dealId, address ?? ZERO],
  });

  const canEdit = isAuthorized === true && deal.active && !isZero(contractAddresses.dealFactory);

  const { writeContract: writeMetadata, data: metaTxHash, isPending: metaPending, reset: resetMeta } = useWriteContract();
  const { status: metaStatus } = useWaitForTransactionReceipt({ hash: metaTxHash });
  useEffect(() => {
    if (metaStatus === "success") {
      toast.success("Metadata updated");
      resetMeta();
      onUpdated?.();
    }
  }, [metaStatus, resetMeta, onUpdated]);

  const { writeContract: writeDeactivate, data: deactTxHash, isPending: deactPending, reset: resetDeact } = useWriteContract();
  const { status: deactStatus } = useWaitForTransactionReceipt({ hash: deactTxHash });
  useEffect(() => {
    if (deactStatus === "success") {
      toast.success("Deal deactivated");
      resetDeact();
      onUpdated?.();
    }
  }, [deactStatus, resetDeact, onUpdated]);

  return (
    <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h3 className="mb-4 text-sm font-medium text-neutral-400">Deal metadata</h3>
      <ValueRow label="Metadata URI" value={deal.metadataURI} mono />
      {deal.metadataURI && (
        <a
          href={deal.metadataURI.startsWith("http") ? deal.metadataURI : `https://ipfs.io/ipfs/${deal.metadataURI.replace("ipfs://", "")}`}
          target="_blank"
          rel="noreferrer"
          className="mt-1 block text-sm text-emerald-500 hover:underline"
        >
          Open link →
        </a>
      )}

      {canEdit && (
        <div className="mt-4 space-y-2">
          <label className="block text-sm text-neutral-500">Update metadata URI</label>
          <input
            type="text"
            value={newUri}
            onChange={(e) => setNewUri(e.target.value)}
            placeholder="ipfs://..."
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-3 py-2 text-sm font-mono"
          />
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => {
                writeMetadata({
                  address: contractAddresses.dealFactory,
                  abi: dealFactoryAbi,
                  functionName: "setDealMetadata",
                  args: [deal.dealId, newUri],
                });
              }}
              disabled={metaPending || newUri === deal.metadataURI}
              className="rounded-lg bg-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-600 disabled:opacity-50"
            >
              {metaPending ? "Updating…" : "Update URI"}
            </button>
            {deal.active && (
              <button
                type="button"
                onClick={() => {
                  writeDeactivate({
                    address: contractAddresses.dealFactory,
                    abi: dealFactoryAbi,
                    functionName: "deactivateDeal",
                    args: [deal.dealId],
                  });
                }}
                disabled={deactPending}
                className="rounded-lg bg-amber-900/50 px-3 py-1.5 text-sm text-amber-400 hover:bg-amber-900/70 disabled:opacity-50"
              >
                {deactPending ? "Deactivating…" : "Deactivate deal"}
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
