import { keccak256 } from "viem";

/** Known deal type labels (protocol-agnostic; SFR/MF/DEV are labels only) */
export const DEAL_TYPE_LABELS: Record<string, string> = {
  [keccak256(new TextEncoder().encode("SFR"))]: "SFR",
  [keccak256(new TextEncoder().encode("MF"))]: "MF",
  [keccak256(new TextEncoder().encode("DEV"))]: "DEV",
};

export function dealTypeToLabel(dealTypeHex: `0x${string}`): string {
  const key = dealTypeHex.toLowerCase();
  return DEAL_TYPE_LABELS[key] ?? `0x${dealTypeHex.slice(2, 18)}…`;
}

export function labelToDealType(label: string): `0x${string}` {
  const normalized = label.toUpperCase().trim();
  if (normalized === "SFR") return keccak256(new TextEncoder().encode("SFR")) as `0x${string}`;
  if (normalized === "MF") return keccak256(new TextEncoder().encode("MF")) as `0x${string}`;
  if (normalized === "DEV") return keccak256(new TextEncoder().encode("DEV")) as `0x${string}`;
  return keccak256(new TextEncoder().encode(normalized)) as `0x${string}`;
}

/** Format requested USDC (6 decimals) for display */
export function formatRequestedUSDC6(raw: bigint | string): string {
  const n = typeof raw === "string" ? BigInt(raw) : raw;
  const whole = n / 1_000_000n;
  const frac = n % 1_000_000n;
  if (frac === 0n) return whole.toString();
  return `${whole}.${frac.toString().padStart(6, "0").replace(/0+$/, "")}`;
}

/** Parse user input (e.g. "500000" or "500000.50") to USDC6 bigint */
export function parseRequestedUSDC6(input: string): bigint {
  const trimmed = input.trim().replace(/,/g, "");
  if (!trimmed) return 0n;
  const [whole = "0", frac = ""] = trimmed.split(".");
  const fracPadded = frac.slice(0, 6).padEnd(6, "0");
  return BigInt(whole) * 1_000_000n + BigInt(fracPadded);
}

/** Collateral asset label from address (optional env-based labels) */
export function collateralAssetLabel(
  address: `0x${string}`,
  envLabels?: { weth?: string; wbtc?: string }
): string {
  const z = "0x0000000000000000000000000000000000000000";
  if (!address || address === z) return "None";
  const a = address.toLowerCase();
  if (envLabels?.weth && a === envLabels.weth.toLowerCase()) return "WETH";
  if (envLabels?.wbtc && a === envLabels.wbtc.toLowerCase()) return "WBTC";
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/** LocalStorage key for "my" deal IDs (sponsor-tracked list for MVP) */
export const DEALS_STORAGE_KEY = "ocx_deal_ids";

export function getStoredDealIds(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(DEALS_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : [];
  } catch {
    return [];
  }
}

export function addStoredDealId(dealId: string): void {
  const ids = getStoredDealIds();
  if (ids.includes(dealId)) return;
  localStorage.setItem(DEALS_STORAGE_KEY, JSON.stringify([...ids, dealId]));
}
