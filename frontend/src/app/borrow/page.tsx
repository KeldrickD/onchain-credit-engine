"use client";

import { useState, useEffect } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits, formatUnits } from "viem";
import toast, { Toaster } from "react-hot-toast";
import Link from "next/link";
import { ConnectButton } from "@/components/ConnectButton";
import { contractAddresses, oracleSignerUrl } from "@/lib/contracts";
import { fetchRiskSignature } from "@/lib/api";
import { loanEngineAbi } from "@/abi/loanEngine";
import { erc20Abi } from "@/abi/erc20";
import { useReadContract } from "wagmi";
import { priceRouterAbi } from "@/abi/priceRouter";

function isZero(addr: `0x${string}`) {
  return addr === "0x0000000000000000000000000000000000000000";
}

export default function BorrowPage() {
  const { address } = useAccount();
  const [depositAmount, setDepositAmount] = useState("");
  const [borrowAmount, setBorrowAmount] = useState("");
  const [step, setStep] = useState<"deposit" | "borrow">("deposit");
  const [riskScore, setRiskScore] = useState("850");
  const [riskTier, setRiskTier] = useState("3");

  const weth = contractAddresses.weth;
  const loanEngine = contractAddresses.loanEngine;
  const hasAddrs = !isZero(loanEngine) && !isZero(weth);

  const { data: maxBorrow } = useReadContract({
    address: hasAddrs ? loanEngine : undefined,
    abi: loanEngineAbi as any,
    functionName: "getMaxBorrow",
    args: address && weth ? [address, weth] : undefined,
  });

  const { data: priceData } = useReadContract({
    address: hasAddrs ? contractAddresses.priceRouter : undefined,
    abi: priceRouterAbi,
    functionName: "getPriceUSD8",
    args: weth ? [weth] : undefined,
  });

  const isStale = priceData?.[2] === true;

  const {
    writeContract: writeApprove,
    data: approveHash,
    isPending: approvePending,
    reset: resetApprove,
  } = useWriteContract();

  const {
    writeContract: writeDeposit,
    data: depositHash,
    isPending: depositPending,
    reset: resetDeposit,
  } = useWriteContract();

  const {
    writeContract: writeOpenLoan,
    data: openLoanHash,
    isPending: openLoanPending,
    reset: resetOpenLoan,
  } = useWriteContract();

  const { status: approveStatus, isError: approveError } = useWaitForTransactionReceipt({
    hash: approveHash,
  });
  useEffect(() => {
    if (approveStatus === "success") {
      toast.success("Approved");
      resetApprove();
    } else if (approveError) {
      toast.error("Approve failed");
      resetApprove();
    }
  }, [approveStatus, approveError, resetApprove]);

  const { status: depositStatus, isError: depositError } = useWaitForTransactionReceipt({
    hash: depositHash,
  });
  useEffect(() => {
    if (depositStatus === "success") {
      toast.success("Collateral deposited");
      resetDeposit();
      setStep("borrow");
      setDepositAmount("");
    } else if (depositError) {
      toast.error("Deposit failed");
      resetDeposit();
    }
  }, [depositStatus, depositError, resetDeposit]);

  const { status: openLoanStatus, isError: openLoanError } = useWaitForTransactionReceipt({
    hash: openLoanHash,
  });
  useEffect(() => {
    if (openLoanStatus === "success") {
      toast.success("Loan opened");
      resetOpenLoan();
      setBorrowAmount("");
    } else if (openLoanError) {
      toast.error("Open loan failed");
      resetOpenLoan();
    }
  }, [openLoanStatus, openLoanError, resetOpenLoan]);

  const handleApproveAndDeposit = () => {
    if (!address || !hasAddrs || !depositAmount) {
      toast.error("Connect wallet and enter amount");
      return;
    }
    const amt = parseUnits(depositAmount, 18);
    if (amt <= 0n) {
      toast.error("Invalid amount");
      return;
    }
    writeApprove({
      address: weth,
      abi: erc20Abi,
      functionName: "approve",
      args: [loanEngine, amt],
    });
  };

  const handleDeposit = () => {
    if (!address || !hasAddrs || !depositAmount) return;
    const amt = parseUnits(depositAmount, 18);
    writeDeposit({
      address: loanEngine,
      abi: loanEngineAbi as any,
      functionName: "depositCollateral",
      args: [weth, amt],
    });
  };

  const handleOpenLoan = async () => {
    if (!address || !hasAddrs || !borrowAmount) {
      toast.error("Connect wallet and enter borrow amount");
      return;
    }
    if (isStale) {
      toast.error("Price is stale - cannot open loan");
      return;
    }
    const amt = parseUnits(borrowAmount, 6);
    if (amt <= 0n) {
      toast.error("Invalid amount");
      return;
    }
    const score = parseInt(riskScore, 10);
    const tier = parseInt(riskTier, 10);
    if (isNaN(score) || isNaN(tier) || score < 0 || score > 1000 || tier < 0 || tier > 5) {
      toast.error("Invalid score/tier");
      return;
    }
    try {
      toast.loading("Fetching risk signature…");
      const { payload, signature } = await fetchRiskSignature(address, score, tier);
      toast.dismiss();
      const riskPayload = {
        user: payload.user as `0x${string}`,
        score: BigInt(payload.score),
        riskTier: BigInt(payload.riskTier),
        timestamp: BigInt(payload.timestamp),
        nonce: BigInt(payload.nonce),
      };
      writeOpenLoan({
        address: loanEngine,
        abi: loanEngineAbi as any,
        functionName: "openLoan",
        args: [weth, amt, riskPayload, signature],
      });
    } catch (e) {
      toast.dismiss();
      toast.error((e as Error).message);
    }
  };

  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <Toaster position="top-right" />
      <header className="mb-10 flex items-center justify-between">
        <Link href="/" className="text-neutral-500 hover:text-neutral-300">
          ← Dashboard
        </Link>
        <ConnectButton />
      </header>

      <h1 className="mb-6 text-2xl font-bold">Borrow</h1>

      {!address ? (
        <p className="text-neutral-500">Connect a wallet to continue.</p>
      ) : !hasAddrs ? (
        <div className="rounded-xl border border-amber-900/50 bg-amber-950/20 p-6">
          <p className="text-amber-600">Contract addresses not configured.</p>
          <p className="mt-2 text-sm text-neutral-500">Set .env.local with deployed addresses.</p>
        </div>
      ) : (
        <div className="space-y-6">
          {isStale && (
            <div className="rounded-lg border border-amber-900/50 bg-amber-950/20 p-3 text-amber-600">
              ⚠ Price is stale — open loan will fail
            </div>
          )}

          <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
            <h2 className="mb-4 text-lg font-semibold">
              {step === "deposit" ? "1. Deposit Collateral (WETH)" : "2. Open Loan"}
            </h2>

            {step === "deposit" ? (
              <div className="space-y-4">
                <div>
                  <label className="mb-1 block text-sm text-neutral-500">Amount (WETH)</label>
                  <input
                    type="text"
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    placeholder="0.0"
                    className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
                  />
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={handleApproveAndDeposit}
                    disabled={approvePending || !depositAmount}
                    className="rounded-lg bg-neutral-700 px-4 py-2 text-sm font-medium hover:bg-neutral-600 disabled:opacity-50"
                  >
                    {approvePending ? "Approving…" : "1. Approve LoanEngine"}
                  </button>
                  <button
                    onClick={handleDeposit}
                    disabled={depositPending || !depositAmount}
                    className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
                  >
                    {depositPending ? "Depositing…" : "2. Deposit (after approve)"}
                  </button>
                </div>
                <p className="text-xs text-neutral-500">
                  Approve WETH to LoanEngine first, then deposit.
                </p>
              </div>
            ) : (
              <div className="space-y-4">
                <p className="text-sm text-neutral-500">
                  Max borrow: {typeof maxBorrow === "bigint" ? formatUnits(maxBorrow, 6) : "—"} USDC
                </p>
                <div>
                  <label className="mb-1 block text-sm text-neutral-500">Borrow amount (USDC)</label>
                  <input
                    type="text"
                    value={borrowAmount}
                    onChange={(e) => setBorrowAmount(e.target.value)}
                    placeholder="0.0"
                    className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
                  />
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <label className="mb-1 block text-sm text-neutral-500">Score (0-1000)</label>
                    <input
                      type="text"
                      value={riskScore}
                      onChange={(e) => setRiskScore(e.target.value)}
                      className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-sm text-neutral-500">Risk Tier (0-5)</label>
                    <input
                      type="text"
                      value={riskTier}
                      onChange={(e) => setRiskTier(e.target.value)}
                      className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
                    />
                  </div>
                </div>
                <button
                  onClick={handleOpenLoan}
                  disabled={openLoanPending || isStale || !borrowAmount}
                  className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
                >
                  {openLoanPending ? "Opening loan…" : "Open Loan"}
                </button>
                <p className="text-xs text-neutral-500">
                  Backend at {oracleSignerUrl} must be running for risk signature.
                </p>
                <button
                  onClick={() => setStep("deposit")}
                  className="text-sm text-neutral-500 hover:text-neutral-300"
                >
                  ← Back to deposit
                </button>
              </div>
            )}
          </section>
        </div>
      )}
    </main>
  );
}
