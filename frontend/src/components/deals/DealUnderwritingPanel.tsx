"use client";

import { useReadContract } from "wagmi";
import { creditRegistryAbi } from "@/abi/creditRegistry";
import { riskEngineV2Abi, reasonCodeToLabel } from "@/abi/riskEngineV2";
import { contractAddresses } from "@/lib/contracts";
import { ValueRow } from "./ValueRow";
import { EvaluateCommitButton } from "./EvaluateCommitButton";

const ZERO = "0x0000000000000000000000000000000000000000";
const STALE_DAYS = 7;

function isZero(a: string) {
  return !a || a === ZERO;
}

type DealUnderwritingPanelProps = {
  dealId: `0x${string}`;
  onCommitted?: () => void;
};

export function DealUnderwritingPanel({ dealId, onCommitted }: DealUnderwritingPanelProps) {
  const hasEngine = !isZero(contractAddresses.riskEngineV2);
  const hasCredit = !isZero(contractAddresses.creditRegistry);

  const { data: profile, refetch: refetchProfile } = useReadContract({
    address: hasCredit ? contractAddresses.creditRegistry : undefined,
    abi: creditRegistryAbi,
    functionName: "getProfile",
    args: [dealId],
  });

  const { data: liveEval, isLoading: evalLoading } = useReadContract({
    address: hasEngine ? contractAddresses.riskEngineV2 : undefined,
    abi: riskEngineV2Abi,
    functionName: "evaluateSubject",
    args: [dealId],
  });

  const lastUpdated = profile?.lastUpdated != null ? Number(profile.lastUpdated) : 0;
  const now = Math.floor(Date.now() / 1000);
  const isStale = lastUpdated > 0 && now - lastUpdated > STALE_DAYS * 86400;

  return (
    <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h3 className="mb-4 text-sm font-medium text-neutral-400">Underwriting</h3>

      <div className="mb-4 rounded-lg border border-neutral-700/50 p-3">
        <p className="mb-2 text-sm font-medium text-neutral-400">CreditRegistry (committed)</p>
        {profile && Number(profile.score) > 0 ? (
          <div className="space-y-1">
            <ValueRow label="Score" value={String(profile.score)} />
            <ValueRow label="Tier" value={String(profile.riskTier)} />
            <ValueRow label="Confidence" value={`${Number(profile.confidenceBps) / 100}%`} />
            <ValueRow label="Model" value={`${String(profile.modelId).slice(0, 18)}…`} mono />
            <ValueRow
              label="Last updated"
              value={
                lastUpdated
                  ? `${new Date(lastUpdated * 1000).toISOString().slice(0, 10)}${isStale ? " (stale)" : ""}`
                  : "—"
              }
            />
          </div>
        ) : (
          <p className="text-sm text-neutral-500">No committed profile yet.</p>
        )}
      </div>

      <div className="mb-4 rounded-lg border border-neutral-700/50 p-3">
        <p className="mb-2 text-sm font-medium text-neutral-400">RiskEngine (live)</p>
        {evalLoading && <p className="text-sm text-neutral-500">Evaluating…</p>}
        {!evalLoading && liveEval && (
          <div className="space-y-1">
            <ValueRow label="Score" value={liveEval.score} />
            <ValueRow label="Tier" value={liveEval.tier} />
            <ValueRow label="Confidence" value={`${Number(liveEval.confidenceBps) / 100}%`} />
            {liveEval.reasonCodes.length > 0 && (
              <div className="mt-2">
                <p className="text-xs text-neutral-500">Reason codes</p>
                <ul className="mt-1 space-y-0.5">
                  {liveEval.reasonCodes.map((code, i) => (
                    <li key={i} className="rounded bg-neutral-800 px-2 py-0.5 font-mono text-xs">
                      {reasonCodeToLabel(code)}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {liveEval.evidence.length > 0 && (
              <div className="mt-2">
                <p className="text-xs text-neutral-500">Evidence</p>
                <ul className="mt-1 space-y-0.5 font-mono text-xs text-neutral-400 break-all">
                  {liveEval.evidence.slice(0, 5).map((id, i) => (
                    <li key={i}>{id}</li>
                  ))}
                  {liveEval.evidence.length > 5 && (
                    <li>+{liveEval.evidence.length - 5} more</li>
                  )}
                </ul>
              </div>
            )}
          </div>
        )}
        {!evalLoading && !liveEval && hasEngine && (
          <p className="text-sm text-neutral-500">No live evaluation (no attestations or model).</p>
        )}
      </div>

      <EvaluateCommitButton
        subjectKey={dealId}
        onCommitted={() => {
          refetchProfile();
          onCommitted?.();
        }}
        disabled={!hasCredit}
      />
    </div>
  );
}
