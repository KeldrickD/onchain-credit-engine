/**
 * Underwriting packet schema v0 — protocol-first export for lenders/LPs/compliance.
 * Chain-agnostic; includes committed profile + live eval.
 */

import { CHAINS, contractAddresses } from "./contracts";
import { dealTypeToLabel } from "./deals";

export type UnderwritingPacketV0 = {
  schema: "ocx-underwriting-packet/v0";
  generatedAt: string; // ISO
  chain: { chainId: number; name: string };
  deal: {
    dealId: string;
    dealType: string; // label e.g. "SFR"
    sponsor: string;
    metadataURI: string;
    collateralAsset: string;
    requestedUSDC6: string;
  };
  creditProfileCommitted: {
    subjectKey: string;
    score: number;
    tier: number;
    confidenceBps: number;
    modelId: string;
    reasonsHash: string;
    evidenceHash: string;
    lastUpdated: number;
  } | null;
  riskEngineLive: {
    score: number;
    tier: number;
    confidenceBps: number;
    modelId: string;
    reasonCodes: string[];
    evidence: string[];
  } | null;
  attestationsLatest: Array<{
    attestationType: string;
    attestationId: string;
    data: string;
    uri: string;
    issuer: string;
    issuedAt: number;
    expiresAt: number;
    valid: boolean;
    revoked: boolean;
  }>;
  contractAddresses: {
    dealFactory: string;
    subjectRegistry: string;
    attestationRegistry: string;
    riskEngineV2: string;
    creditRegistry: string;
  };
  notes: string[];
};

const CHAIN_NAMES: Record<number, string> = {
  [CHAINS.baseSepolia]: "Base Sepolia",
};

function getChainName(chainId: number): string {
  return CHAIN_NAMES[chainId] ?? `Chain ${chainId}`;
}

/** Build packet from raw deal + profile + eval + attestations (all optional where applicable) */
export function buildUnderwritingPacket(params: {
  dealId: string;
  dealType: `0x${string}`;
  sponsor: string;
  metadataURI: string;
  collateralAsset: string;
  requestedUSDC6: string;
  chainId?: number;
  committedProfile?: {
    score: bigint | number;
    riskTier: bigint | number;
    confidenceBps: number;
    modelId: `0x${string}`;
    reasonsHash: `0x${string}`;
    evidenceHash: `0x${string}`;
    lastUpdated: bigint | number;
  } | null;
  liveEval?: {
    score: number;
    tier: number;
    confidenceBps: number;
    modelId: string;
    reasonCodes: readonly `0x${string}`[] | string[];
    evidence: readonly `0x${string}`[] | string[];
  } | null;
  attestationsLatest?: Array<{
    attestationType: string;
    attestationId: string;
    data: string;
    uri: string;
    issuer: string;
    issuedAt: number;
    expiresAt: number;
    valid: boolean;
    revoked: boolean;
  }>;
}): UnderwritingPacketV0 {
  const chainId = params.chainId ?? CHAINS.baseSepolia;
  const committed = params.committedProfile;
  const live = params.liveEval;

  return {
    schema: "ocx-underwriting-packet/v0",
    generatedAt: new Date().toISOString(),
    chain: { chainId, name: getChainName(chainId) },
    deal: {
      dealId: params.dealId,
      dealType: dealTypeToLabel(params.dealType),
      sponsor: params.sponsor,
      metadataURI: params.metadataURI,
      collateralAsset: params.collateralAsset,
      requestedUSDC6: params.requestedUSDC6,
    },
    creditProfileCommitted: committed
      ? {
          subjectKey: params.dealId,
          score: Number(committed.score),
          tier: Number(committed.riskTier),
          confidenceBps: committed.confidenceBps,
          modelId: committed.modelId,
          reasonsHash: committed.reasonsHash,
          evidenceHash: committed.evidenceHash,
          lastUpdated: Number(committed.lastUpdated),
        }
      : null,
    riskEngineLive: live
      ? {
          score: live.score,
          tier: live.tier,
          confidenceBps: live.confidenceBps,
          modelId: live.modelId,
          reasonCodes: live.reasonCodes.map(String),
          evidence: live.evidence.map(String),
        }
      : null,
    attestationsLatest: params.attestationsLatest ?? [],
    contractAddresses: {
      dealFactory: contractAddresses.dealFactory,
      subjectRegistry: contractAddresses.subjectRegistry,
      attestationRegistry: contractAddresses.attestationRegistry,
      riskEngineV2: contractAddresses.riskEngineV2,
      creditRegistry: contractAddresses.creditRegistry,
    },
    notes: [
      "This packet is an export of onchain state and model output. It is not financial advice.",
    ],
  };
}

/** Trigger download of packet JSON */
export function downloadUnderwritingPacket(packet: UnderwritingPacketV0, dealIdShort?: string): void {
  const name = dealIdShort
    ? `underwriting-packet-${dealIdShort}.json`
    : `underwriting-packet-${packet.deal.dealId.slice(0, 10)}.json`;
  const blob = new Blob([JSON.stringify(packet, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}
