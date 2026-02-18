"use client";

import { useEffect } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import toast from "react-hot-toast";
import { creditRegistryAbi } from "@/abi/creditRegistry";
import { contractAddresses } from "@/lib/contracts";
import { fetchRiskEvaluateSubjectAndSignature } from "@/lib/api";

type EvaluateCommitButtonProps = {
  subjectKey: `0x${string}`;
  onCommitted?: () => void;
  disabled?: boolean;
  className?: string;
};

const ZERO = "0x0000000000000000000000000000000000000000";

export function EvaluateCommitButton({
  subjectKey,
  onCommitted,
  disabled,
  className = "",
}: EvaluateCommitButtonProps) {
  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
    reset,
  } = useWriteContract();
  const { status } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (status === "success") {
      toast.success("Risk committed to CreditRegistry");
      reset();
      onCommitted?.();
    } else if (status === "error") {
      toast.error("Commit failed");
      reset();
    }
  }, [status, reset, onCommitted]);

  const handleClick = async () => {
    if (contractAddresses.creditRegistry === ZERO) {
      toast.error("CreditRegistry not configured");
      return;
    }
    try {
      toast.loading("Evaluating subject and signing…");
      const res = await fetchRiskEvaluateSubjectAndSignature(subjectKey);
      toast.dismiss();
      toast.loading("Submitting commit tx…");
      writeContract({
        address: contractAddresses.creditRegistry,
        abi: creditRegistryAbi,
        functionName: "updateCreditProfileV2ByKey",
        args: [
          {
            subjectKey: res.payload.subjectKey as `0x${string}`,
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
    <div className="space-y-1">
      <button
        type="button"
        onClick={handleClick}
        disabled={disabled || isPending}
        className={`rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50 ${className}`}
      >
        {isPending ? "Committing…" : "Evaluate & Commit"}
      </button>
      {writeError && <p className="text-sm text-red-400">{writeError.message}</p>}
    </div>
  );
}
