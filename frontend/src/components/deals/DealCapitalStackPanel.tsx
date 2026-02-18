"use client";

import { useState } from "react";
import { postCapitalStackSuggest } from "@/lib/api";
import type { UnderwritingPacketV0 } from "@/lib/underwriting-packet";
import type { CapitalStackSuggestResponse, Overrides } from "@/lib/capital-stack";

function formatPct(n: number): string {
  return `${n.toFixed(1)}%`;
}

function formatUSDC6(raw: string): string {
  const n = BigInt(raw);
  const whole = n / 1_000_000n;
  const frac = n % 1_000_000n;
  if (frac === 0n) return whole.toString();
  return `${whole}.${frac.toString().padStart(6, "0").replace(/0+$/, "")}`;
}

function formatBpsAsPct(bps: number): string {
  return `${(bps / 100).toFixed(2)}%`;
}

type DealCapitalStackPanelProps = {
  /** Pre-built packet (optional if buildPacket is provided). */
  packet?: UnderwritingPacketV0 | null;
  /** Callback to build packet (e.g. from parent state). Used when user clicks Generate if packet not provided. */
  buildPacket?: () => UnderwritingPacketV0 | null;
};

export function DealCapitalStackPanel({ packet: packetProp, buildPacket }: DealCapitalStackPanelProps) {
  const [result, setResult] = useState<CapitalStackSuggestResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [overrides, setOverrides] = useState<Overrides>({});
  const [seniorBias, setSeniorBias] = useState(0);

  const handleSuggest = async () => {
    const packet = packetProp ?? buildPacket?.() ?? null;
    if (!packet) {
      setError("Build underwriting packet first (deal + profile + attestations).");
      return;
    }
    setError(null);
    setLoading(true);
    try {
      const overridesToSend: Overrides = { ...overrides };
      if (seniorBias !== 0) overridesToSend.seniorBiasBps = seniorBias;
      const res = await postCapitalStackSuggest({ packet, overrides: overridesToSend });
      setResult(res);
    } catch (e) {
      setError((e as Error).message);
      setResult(null);
    } finally {
      setLoading(false);
    }
  };

  const handleDownloadJson = () => {
    if (!result) return;
    const blob = new Blob([JSON.stringify(result, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `capital-stack-${result.dealId ?? "deal"}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h3 className="mb-4 text-sm font-medium text-neutral-400">Suggested Capital Stack</h3>

      {!packetProp && !buildPacket && (
        <p className="text-sm text-neutral-500">
          Pass buildPacket from the deal page so the stack can use tier, confidence, and attestations.
        </p>
      )}

      <div className="mt-4 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={handleSuggest}
          disabled={(!packetProp && !buildPacket) || loading}
          className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
        >
          {loading ? "Generating…" : "Generate stack"}
        </button>
      </div>

      {error && <p className="mt-2 text-sm text-red-400">{error}</p>}

      {result && (
        <div className="mt-6 space-y-4">
          <div className="overflow-x-auto rounded-lg border border-neutral-700/50">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-neutral-700 text-left text-neutral-500">
                  <th className="p-2">Tranche</th>
                  <th className="p-2">%</th>
                  <th className="p-2">USDC (6d)</th>
                  <th className="p-2">Pricing</th>
                </tr>
              </thead>
              <tbody>
                <tr className="border-b border-neutral-700/50">
                  <td className="p-2 font-medium">Senior</td>
                  <td className="p-2">{formatPct(result.stack.seniorPct)}</td>
                  <td className="p-2 font-mono">{formatUSDC6(result.stack.seniorUSDC6)}</td>
                  <td className="p-2">{formatBpsAsPct(result.pricing.seniorAprBps)} APR</td>
                </tr>
                <tr className="border-b border-neutral-700/50">
                  <td className="p-2 font-medium">Mezz</td>
                  <td className="p-2">{formatPct(result.stack.mezzPct)}</td>
                  <td className="p-2 font-mono">{formatUSDC6(result.stack.mezzUSDC6)}</td>
                  <td className="p-2">{formatBpsAsPct(result.pricing.mezzAprBps)} APR</td>
                </tr>
                <tr className="border-b border-neutral-700/50">
                  <td className="p-2 font-medium">Pref</td>
                  <td className="p-2">{formatPct(result.stack.prefPct)}</td>
                  <td className="p-2 font-mono">{formatUSDC6(result.stack.prefUSDC6)}</td>
                  <td className="p-2">{formatBpsAsPct(result.pricing.prefReturnBps)} return</td>
                </tr>
                <tr>
                  <td className="p-2 font-medium">Common</td>
                  <td className="p-2">{formatPct(result.stack.commonPct)}</td>
                  <td className="p-2 font-mono">{formatUSDC6(result.stack.commonUSDC6)}</td>
                  <td className="p-2 text-neutral-500">residual</td>
                </tr>
              </tbody>
            </table>
          </div>

          {result.rationale.length > 0 && (
            <div>
              <p className="mb-1 text-xs font-medium text-neutral-500">Rationale</p>
              <ul className="list-inside list-disc space-y-0.5 text-sm text-neutral-400">
                {result.rationale.map((r, i) => (
                  <li key={i}>{r}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            <label className="flex items-center gap-2 text-sm text-neutral-500">
              <span>Senior bias (bps):</span>
              <input
                type="number"
                min={-2000}
                max={2000}
                step={100}
                value={seniorBias}
                onChange={(e) => setSeniorBias(Number(e.target.value) || 0)}
                className="w-24 rounded border border-neutral-700 bg-neutral-800 px-2 py-1 text-sm"
              />
            </label>
          </div>

          <button
            type="button"
            onClick={handleDownloadJson}
            className="rounded-lg border border-neutral-600 bg-neutral-800 px-3 py-1.5 text-sm hover:bg-neutral-700"
          >
            Download Stack Plan JSON
          </button>
        </div>
      )}
    </div>
  );
}
