"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import toast from "react-hot-toast";
import { dealFactoryAbi } from "@/abi/dealFactory";
import { contractAddresses } from "@/lib/contracts";
import { labelToDealType, parseRequestedUSDC6, addStoredDealId } from "@/lib/deals";

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

const DEAL_TYPE_OPTIONS = [
  { value: "SFR", label: "SFR" },
  { value: "MF", label: "MF" },
  { value: "DEV", label: "DEV" },
];

export function DealCreateForm() {
  const router = useRouter();
  const { address, isConnected } = useAccount();
  const [dealType, setDealType] = useState("SFR");
  const [metadataURI, setMetadataURI] = useState("");
  const [collateralChoice, setCollateralChoice] = useState<"none" | "weth" | "wbtc">("none");
  const [requestedInput, setRequestedInput] = useState("");

  const collateralAsset =
    collateralChoice === "weth"
      ? contractAddresses.weth
      : collateralChoice === "wbtc"
        ? contractAddresses.wbtc
        : ZERO;

  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
    reset,
  } = useWriteContract();
  const { data: receipt, status } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (status !== "success" || !receipt || !txHash) return;
    const factoryAddress = contractAddresses.dealFactory.toLowerCase();
    const log = receipt.logs.find(
      (l) => l.address.toLowerCase() === factoryAddress && l.topics.length >= 2
    );
    if (log?.topics[1]) {
      const dealId = log.topics[1] as `0x${string}`;
      addStoredDealId(dealId);
      toast.success("Deal created");
      reset();
      router.push(`/deals/${dealId}`);
    } else {
      toast.success("Deal created. Add the deal ID from the transaction to your list.");
      reset();
      router.push("/deals");
    }
  }, [status, receipt, txHash, reset, router]);

  const handleCreate = () => {
    if (!isConnected || !address) {
      toast.error("Connect wallet");
      return;
    }
    const uri = metadataURI.trim() || "ipfs://";
    const requested = parseRequestedUSDC6(requestedInput);
    if (requested <= 0n) {
      toast.error("Enter requested USDC amount");
      return;
    }
    const typeBytes = labelToDealType(dealType);
    writeContract({
      address: contractAddresses.dealFactory,
      abi: dealFactoryAbi,
      functionName: "createDeal",
      args: [typeBytes, uri, collateralAsset, requested],
    });
  };

  return (
    <form
      className="space-y-4 max-w-lg"
      onSubmit={(e) => {
        e.preventDefault();
        handleCreate();
      }}
    >
      <div>
        <label className="mb-1 block text-sm text-neutral-500">Deal type</label>
        <select
          value={dealType}
          onChange={(e) => setDealType(e.target.value)}
          className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm"
        >
          {DEAL_TYPE_OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="mb-1 block text-sm text-neutral-500">Metadata URI (e.g. ipfs://…)</label>
        <input
          type="text"
          value={metadataURI}
          onChange={(e) => setMetadataURI(e.target.value)}
          placeholder="ipfs://Qm..."
          className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm font-mono"
        />
      </div>
      <div>
        <label className="mb-1 block text-sm text-neutral-500">Collateral asset</label>
        <select
          value={collateralChoice}
          onChange={(e) => setCollateralChoice(e.target.value as "none" | "weth" | "wbtc")}
          className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm"
        >
          <option value="none">None</option>
          <option value="weth">WETH</option>
          <option value="wbtc">WBTC</option>
        </select>
      </div>
      <div>
        <label className="mb-1 block text-sm text-neutral-500">Requested USDC (6 decimals)</label>
        <input
          type="text"
          value={requestedInput}
          onChange={(e) => setRequestedInput(e.target.value)}
          placeholder="500000"
          className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm"
        />
      </div>
      <button
        type="submit"
        disabled={isPending || !isConnected}
        className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
      >
        {isPending ? "Creating…" : "Create deal"}
      </button>
      {writeError && <p className="text-sm text-red-400">{writeError.message}</p>}
    </form>
  );
}
