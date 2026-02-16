"use client";

import { useState, useEffect } from "react";
import { isAddress } from "viem";
import { contractAddresses } from "@/lib/contracts";

const PRESETS = [
  { label: "WETH", value: "weth" },
  { label: "WBTC", value: "wbtc" },
  { label: "Custom address", value: "custom" },
] as const;

type AssetSelectorProps = {
  value: `0x${string}` | null;
  onChange: (addr: `0x${string}` | null) => void;
  disabled?: boolean;
};

function isZero(addr: `0x${string}`) {
  return addr === "0x0000000000000000000000000000000000000000";
}

function modeFromValue(value: `0x${string}` | null): "weth" | "wbtc" | "custom" {
  if (!value) return "weth";
  const v = value.toLowerCase();
  if (v === contractAddresses.weth.toLowerCase() && !isZero(contractAddresses.weth))
    return "weth";
  if (v === contractAddresses.wbtc.toLowerCase() && !isZero(contractAddresses.wbtc))
    return "wbtc";
  return "custom";
}

export function AssetSelector({ value, onChange, disabled }: AssetSelectorProps) {
  const [mode, setMode] = useState<"weth" | "wbtc" | "custom">(() => modeFromValue(value));
  const [customAddr, setCustomAddr] = useState(
    modeFromValue(value) === "custom" && value ? value : ""
  );

  useEffect(() => {
    const m = modeFromValue(value);
    setMode(m);
    if (m === "custom" && value) setCustomAddr(value);
  }, [value]);

  const handlePreset = (p: (typeof PRESETS)[number]["value"]) => {
    if (p === "custom") {
      setMode("custom");
      onChange(null);
      return;
    }
    setMode(p);
    const addr = p === "weth" ? contractAddresses.weth : contractAddresses.wbtc;
    onChange(isZero(addr) ? null : addr);
  };

  const handleCustomChange = (raw: string) => {
    setCustomAddr(raw);
    const trimmed = raw.trim();
    if (trimmed && isAddress(trimmed)) {
      onChange(trimmed as `0x${string}`);
    } else {
      onChange(null);
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        {PRESETS.map((p) => (
          <button
            key={p.value}
            type="button"
            onClick={() => handlePreset(p.value)}
            disabled={disabled}
            className={`rounded-lg px-3 py-1.5 text-sm font-medium ${
              mode === p.value
                ? "bg-neutral-600 text-white"
                : "bg-neutral-800 text-neutral-400 hover:bg-neutral-700"
            } disabled:opacity-50`}
          >
            {p.label}
          </button>
        ))}
      </div>
      {mode === "custom" && (
        <input
          type="text"
          value={customAddr}
          onChange={(e) => handleCustomChange(e.target.value)}
          placeholder="0x..."
          disabled={disabled}
          className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
        />
      )}
    </div>
  );
}
