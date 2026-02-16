"use client";

import { useState, useEffect } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { parseUnits, formatUnits } from "viem";
import toast, { Toaster } from "react-hot-toast";
import Link from "next/link";
import { ConnectButton } from "@/components/ConnectButton";
import { contractAddresses } from "@/lib/contracts";
import { loanEngineAbi } from "@/abi/loanEngine";
import { erc20Abi } from "@/abi/erc20";

function isZero(addr: `0x${string}`) {
  return addr === "0x0000000000000000000000000000000000000000";
}

export default function RepayPage() {
  const { address } = useAccount();
  const [repayAmount, setRepayAmount] = useState("");

  const loanEngine = contractAddresses.loanEngine;
  const vault = contractAddresses.treasuryVault;
  const usdc = contractAddresses.usdc;
  const hasAddrs = !isZero(loanEngine) && !isZero(vault) && !isZero(usdc);

  const { data: position } = useReadContract({
    address: hasAddrs ? loanEngine : undefined,
    abi: loanEngineAbi as any,
    functionName: "getPosition",
    args: address ? [address] : undefined,
  });

  const principal = (position && typeof position === "object" && "principalAmount" in position
    ? (position as { principalAmount: bigint }).principalAmount
    : 0n);

  const {
    writeContract: writeApprove,
    data: approveHash,
    isPending: approvePending,
    reset: resetApprove,
  } = useWriteContract();

  const {
    writeContract: writeRepay,
    data: repayHash,
    isPending: repayPending,
    reset: resetRepay,
  } = useWriteContract();

  const { status: approveStatus, isError: approveError } = useWaitForTransactionReceipt({
    hash: approveHash,
  });
  useEffect(() => {
    if (approveStatus === "success") {
      toast.success("USDC approved");
      resetApprove();
    } else if (approveError) {
      toast.error("Approve failed");
      resetApprove();
    }
  }, [approveStatus, approveError, resetApprove]);

  const { status: repayStatus, isError: repayError } = useWaitForTransactionReceipt({
    hash: repayHash,
  });
  useEffect(() => {
    if (repayStatus === "success") {
      toast.success("Repaid");
      resetRepay();
      setRepayAmount("");
    } else if (repayError) {
      toast.error("Repay failed");
      resetRepay();
    }
  }, [repayStatus, repayError, resetRepay]);

  const handleApprove = () => {
    if (!address || !hasAddrs || !repayAmount) {
      toast.error("Connect wallet and enter amount");
      return;
    }
    const amt = parseUnits(repayAmount, 6);
    if (amt <= 0n) {
      toast.error("Invalid amount");
      return;
    }
    writeApprove({
      address: usdc,
      abi: erc20Abi,
      functionName: "approve",
      args: [vault, amt],
    });
  };

  const handleRepay = () => {
    if (!address || !hasAddrs || !repayAmount) return;
    const amt = parseUnits(repayAmount, 6);
    if (amt <= 0n) return;
    if (amt > principal) {
      toast.error("Amount exceeds debt");
      return;
    }
    writeRepay({
      address: loanEngine,
      abi: loanEngineAbi as any,
      functionName: "repay",
      args: [amt],
    });
  };

  const projectedRemaining = (() => {
    if (!repayAmount || principal === 0n) return null;
    try {
      const amt = parseUnits(repayAmount, 6);
      if (amt >= principal) return 0n;
      return principal - amt;
    } catch {
      return null;
    }
  })();

  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <Toaster position="top-right" />
      <header className="mb-10 flex items-center justify-between">
        <Link href="/" className="text-neutral-500 hover:text-neutral-300">
          ← Dashboard
        </Link>
        <ConnectButton />
      </header>

      <h1 className="mb-6 text-2xl font-bold">Repay</h1>

      {!address ? (
        <p className="text-neutral-500">Connect a wallet to continue.</p>
      ) : !hasAddrs ? (
        <div className="rounded-xl border border-amber-900/50 bg-amber-950/20 p-6">
          <p className="text-amber-600">Contract addresses not configured.</p>
          <p className="mt-2 text-sm text-neutral-500">
            Set TREASURY_VAULT_ADDRESS and USDC_ADDRESS in .env.local.
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
            <h2 className="mb-4 text-lg font-semibold">Current Debt</h2>
            <p className="font-mono text-lg">
              {formatUnits(principal, 6)} USDC
            </p>
            {principal === 0n && (
              <p className="mt-2 text-sm text-neutral-500">No active loan.</p>
            )}
          </section>

          {principal > 0n && (
            <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
              <h2 className="mb-4 text-lg font-semibold">Repay</h2>
              <div className="space-y-4">
                <div>
                  <label className="mb-1 block text-sm text-neutral-500">Amount (USDC)</label>
                  <input
                    type="text"
                    value={repayAmount}
                    onChange={(e) => setRepayAmount(e.target.value)}
                    placeholder="0.0"
                    className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
                  />
                </div>
                {projectedRemaining !== null && (
                  <p className="text-sm text-neutral-500">
                    Projected remaining: {formatUnits(projectedRemaining, 6)} USDC
                  </p>
                )}
                <div className="flex gap-2">
                  <button
                    onClick={handleApprove}
                    disabled={approvePending || !repayAmount}
                    className="rounded-lg bg-neutral-700 px-4 py-2 text-sm font-medium hover:bg-neutral-600 disabled:opacity-50"
                  >
                    {approvePending ? "Approving…" : "Approve Vault"}
                  </button>
                  <button
                    onClick={handleRepay}
                    disabled={repayPending || !repayAmount}
                    className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
                  >
                    {repayPending ? "Repaying…" : "Repay"}
                  </button>
                </div>
                <p className="text-xs text-neutral-500">
                  Approve USDC to TreasuryVault first (vault pulls from you).
                </p>
              </div>
            </section>
          )}
        </div>
      )}
    </main>
  );
}
