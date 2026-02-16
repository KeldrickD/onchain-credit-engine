"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAccount, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import toast, { Toaster } from "react-hot-toast";
import { ConnectButton } from "@/components/ConnectButton";
import { contractAddresses } from "@/lib/contracts";
import { riskEngineV2Abi, reasonCodeToLabel } from "@/abi/riskEngineV2";
import { creditRegistryAbi } from "@/abi/creditRegistry";
import { fetchRiskEvaluationAndSignature } from "@/lib/api";

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

function isZero(addr: `0x${string}` | null) {
  return !addr || addr === ZERO;
}

export default function RiskPage() {
  const { address } = useAccount();
  const [subjectInput, setSubjectInput] = useState("");
  const subject = subjectInput.trim().startsWith("0x") && subjectInput.trim().length === 42
    ? (subjectInput.trim() as `0x${string}`)
    : (address ?? undefined);

  const hasEngine = !isZero(contractAddresses.riskEngineV2);
  const hasCreditRegistry = !isZero(contractAddresses.creditRegistry);

  const { data: output, isLoading, error, refetch: refetchRisk } = useReadContract({
    address: hasEngine ? contractAddresses.riskEngineV2 : undefined,
    abi: riskEngineV2Abi,
    functionName: "evaluate",
    args: subject ? [subject] : undefined,
  });
  const { data: creditProfile, refetch: refetchCreditProfile } = useReadContract({
    address: hasCreditRegistry ? contractAddresses.creditRegistry : undefined,
    abi: creditRegistryAbi,
    functionName: "getCreditProfile",
    args: subject ? [subject] : undefined,
  });

  const {
    writeContract: writeCommitRisk,
    data: commitHash,
    error: commitError,
    isPending: commitPending,
    reset: resetCommit,
  } = useWriteContract();
  const { status: commitStatus } = useWaitForTransactionReceipt({ hash: commitHash });
  useEffect(() => {
    if (commitStatus === "success") {
      toast.dismiss();
      toast.success("Risk committed to CreditRegistry");
      resetCommit();
      refetchRisk();
      refetchCreditProfile();
    } else if (commitStatus === "error") {
      toast.dismiss();
      toast.error("Commit failed");
      resetCommit();
    }
  }, [commitStatus, resetCommit, refetchRisk, refetchCreditProfile]);

  const handleCommit = async () => {
    if (!subject || !hasCreditRegistry) return;
    try {
      toast.loading("Evaluating and signing…");
      const res = await fetchRiskEvaluationAndSignature(subject);
      toast.dismiss();
      toast.loading("Submitting commit tx…");
      writeCommitRisk({
        address: contractAddresses.creditRegistry,
        abi: creditRegistryAbi,
        functionName: "updateCreditProfileV2",
        args: [
          {
            user: res.payload.user as `0x${string}`,
            score: Number(res.payload.score),
            riskTier: Number(res.payload.riskTier),
            confidenceBps: Number(res.payload.confidenceBps),
            modelId: res.payload.modelId,
            reasonsHash: res.payload.reasonsHash,
            evidenceHash: res.payload.evidenceHash,
            timestamp: BigInt(res.payload.timestamp),
            nonce: BigInt(res.payload.nonce),
          },
          res.signature,
        ],
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

      <h1 className="mb-2 text-2xl font-bold">Risk Profile</h1>
      <p className="mb-6 text-neutral-500">
        Deterministic score, tier, confidence, reason codes, and evidence
      </p>

      {!hasEngine && (
        <div className="mb-6 rounded-xl border border-amber-900/50 bg-amber-950/20 p-4">
          <p className="text-amber-600">RiskEngineV2 not configured</p>
          <p className="mt-1 text-sm text-neutral-500">Set NEXT_PUBLIC_RISK_ENGINE_V2_ADDRESS</p>
        </div>
      )}

      <div className="mb-6">
        <label className="mb-1 block text-sm text-neutral-500">Subject address</label>
        <input
          type="text"
          value={subjectInput}
          onChange={(e) => setSubjectInput(e.target.value)}
          placeholder={address ?? "0x..."}
          className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
        />
        <p className="mt-1 text-xs text-neutral-500">
          Leave empty to use connected wallet. Or enter any address.
        </p>
      </div>

      {!subject && (
        <p className="text-neutral-500">Connect wallet or enter an address to view risk profile.</p>
      )}

      {subject && (
        <div className="space-y-6">
          {isLoading && <p className="text-neutral-500">Evaluating…</p>}
          {error && <p className="text-red-400">{String(error.message)}</p>}

          {output && (
            <div className="space-y-6 rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div>
                  <p className="text-sm text-neutral-500">Score</p>
                  <p className="text-2xl font-bold">{output.score}</p>
                </div>
                <div>
                  <p className="text-sm text-neutral-500">Tier</p>
                  <p className="text-2xl font-bold">{output.tier}</p>
                </div>
                <div>
                  <p className="text-sm text-neutral-500">Confidence</p>
                  <p className="text-2xl font-bold">{(Number(output.confidenceBps) / 100).toFixed(1)}%</p>
                </div>
                <div>
                  <p className="text-sm text-neutral-500">Model</p>
                  <p className="font-mono text-sm">{output.modelId.slice(0, 18)}…</p>
                </div>
              </div>

              <div className="rounded-lg border border-neutral-700/50 p-3">
                <p className="mb-1 text-sm font-medium text-neutral-400">CreditRegistry (onchain committed)</p>
                {creditProfile ? (
                  <div className="space-y-1 text-sm">
                    <p>Score: {String(creditProfile.score)}</p>
                    <p>Tier: {String(creditProfile.riskTier)}</p>
                    <p>Confidence: {(Number(creditProfile.confidenceBps) / 100).toFixed(1)}%</p>
                    <p className="font-mono text-xs">Model: {String(creditProfile.modelId).slice(0, 18)}…</p>
                  </div>
                ) : (
                  <p className="text-sm text-neutral-500">No committed profile yet.</p>
                )}
              </div>

              <div className="space-y-2">
                <button
                  onClick={handleCommit}
                  disabled={commitPending || !hasCreditRegistry}
                  className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
                >
                  {commitPending ? "Committing…" : "Evaluate & Commit to Registry"}
                </button>
                {!hasCreditRegistry && (
                  <p className="text-xs text-amber-600">Set NEXT_PUBLIC_CREDIT_REGISTRY_ADDRESS to enable commit.</p>
                )}
                {commitHash && (
                  <a
                    href={`https://sepolia.basescan.org/tx/${commitHash}`}
                    target="_blank"
                    rel="noreferrer"
                    className="block text-sm text-emerald-500 hover:underline"
                  >
                    View commit tx →
                  </a>
                )}
                {commitError && <p className="text-sm text-red-400">{commitError.message}</p>}
              </div>

              {output.reasonCodes.length > 0 && (
                <div>
                  <p className="mb-2 text-sm font-medium text-neutral-400">Reason codes</p>
                  <ul className="space-y-1">
                    {output.reasonCodes.map((code, i) => (
                      <li key={i} className="rounded bg-neutral-800 px-3 py-1.5 font-mono text-sm">
                        {reasonCodeToLabel(code)}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {output.evidence.length > 0 && (
                <div>
                  <p className="mb-2 text-sm font-medium text-neutral-400">Evidence (attestation IDs)</p>
                  <ul className="space-y-1">
                    {output.evidence.map((id, i) => (
                      <li key={i} className="font-mono text-xs text-neutral-500 break-all">
                        {id}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </main>
  );
}
