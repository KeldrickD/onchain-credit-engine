"use client";

import { useParams } from "next/navigation";
import Link from "next/link";
import { useReadContract, useReadContracts } from "wagmi";
import { keccak256 } from "viem";
import { ConnectButton } from "@/components/ConnectButton";
import { DealHeader } from "@/components/deals/DealHeader";
import { DealMetadataPanel } from "@/components/deals/DealMetadataPanel";
import { DealUnderwritingPanel } from "@/components/deals/DealUnderwritingPanel";
import { DealAttestationsPanel, type AttestationRow } from "@/components/deals/DealAttestationsPanel";
import { UnderwritingPacketExportButton } from "@/components/deals/UnderwritingPacketExportButton";
import { DealCapitalStackPanel } from "@/components/deals/DealCapitalStackPanel";
import { dealFactoryAbi } from "@/abi/dealFactory";
import { creditRegistryAbi } from "@/abi/creditRegistry";
import { riskEngineV2Abi } from "@/abi/riskEngineV2";
import { attestationRegistryAbi } from "@/abi/attestationRegistry";
import { contractAddresses } from "@/lib/contracts";
import { buildUnderwritingPacket } from "@/lib/underwriting-packet";

const ZERO = "0x0000000000000000000000000000000000000000";
const COMMON_TYPES = ["DSCR_BPS", "NOI_USD6", "KYB_PASS", "SPONSOR_TRACK"].map((label) => ({
  label,
  hash: keccak256(new TextEncoder().encode(label)) as `0x${string}`,
}));

function isZero(a: string) {
  return !a || a === ZERO;
}

export default function DealDetailPage() {
  const params = useParams();
  const dealIdParam = typeof params?.dealId === "string" ? params.dealId : "";
  const dealId = dealIdParam.startsWith("0x") && dealIdParam.length === 66 ? (dealIdParam as `0x${string}`) : null;

  const hasFactory = !isZero(contractAddresses.dealFactory);
  const hasRegistry = !isZero(contractAddresses.attestationRegistry);

  const { data: dealRaw, refetch: refetchDeal } = useReadContract({
    address: hasFactory ? contractAddresses.dealFactory : undefined,
    abi: dealFactoryAbi,
    functionName: "getDeal",
    args: dealId ? [dealId] : undefined,
  });

  const { data: profile, refetch: refetchProfile } = useReadContract({
    address: contractAddresses.creditRegistry,
    abi: creditRegistryAbi,
    functionName: "getProfile",
    args: dealId ? [dealId] : undefined,
  });

  const { data: liveEval } = useReadContract({
    address: contractAddresses.riskEngineV2,
    abi: riskEngineV2Abi,
    functionName: "evaluateSubject",
    args: dealId ? [dealId] : undefined,
  });

  const idCalls =
    dealId && hasRegistry
      ? COMMON_TYPES.map(({ hash }) => ({
          address: contractAddresses.attestationRegistry,
          abi: attestationRegistryAbi,
          functionName: "getLatestSubjectAttestationId" as const,
          args: [dealId, hash],
        }))
      : [];
  const { data: idResults } = useReadContracts({ contracts: idCalls });

  const attestationIds = (idResults ?? []).map((r) => {
    if (r.status !== "success" || !r.result) return null;
    const id = r.result as `0x${string}`;
    return id === "0x0000000000000000000000000000000000000000000000000000000000000000" ? null : id;
  });

  const fetchCalls = attestationIds
    .filter((id): id is `0x${string}` => id != null)
    .map((id) => ({
      address: contractAddresses.attestationRegistry,
      abi: attestationRegistryAbi,
      functionName: "getSubjectAttestation" as const,
      args: [id],
    }));
  const { data: attResults } = useReadContracts({ contracts: fetchCalls });

  const nonNullIds = attestationIds.filter((id): id is `0x${string}` => id != null);
  const attestationsForPanel = COMMON_TYPES.map(({ label }, i) => {
    const id = attestationIds[i];
    if (id == null) return null;
    const k = nonNullIds.indexOf(id);
    const r = attResults?.[k];
    const tuple = r?.status === "success" && r?.result ? (r.result as [unknown, boolean, boolean]) : null;
    const att = tuple
      ? (tuple[0] as {
          data?: bigint | string;
          uri?: string;
          issuedAt?: bigint;
          expiresAt?: bigint;
          issuer?: `0x${string}`;
        })
      : null;
    const revoked = tuple ? tuple[1] : false;
    const expired = tuple ? tuple[2] : false;
    const row: AttestationRow = {
      label,
      attestationId: id,
      data: att?.data != null ? String(att.data) : "",
      uri: att?.uri ?? "",
      issuer: att?.issuer ?? "",
      issuedAt: att?.issuedAt != null ? Number(att.issuedAt) : 0,
      expiresAt: att?.expiresAt != null ? Number(att.expiresAt) : 0,
      valid: !revoked && !expired,
      revoked,
    };
    return row.data !== "" || row.uri !== "" || row.issuedAt > 0 ? row : null;
  }).filter((x): x is AttestationRow => x != null);

  const deal = dealRaw as
    | {
        dealId: `0x${string}`;
        sponsor: `0x${string}`;
        dealType: `0x${string}`;
        metadataURI: string;
        collateralAsset: `0x${string}`;
        requestedUSDC6: bigint;
        createdAt: bigint;
        active: boolean;
      }
    | undefined;

  const buildPacket = () =>
    buildUnderwritingPacket({
      dealId: dealId ?? "0x",
      dealType: deal?.dealType ?? ("0x" as `0x${string}`),
      sponsor: deal?.sponsor ?? "",
      metadataURI: deal?.metadataURI ?? "",
      collateralAsset: deal?.collateralAsset ?? "",
      requestedUSDC6: deal?.requestedUSDC6 != null ? String(deal.requestedUSDC6) : "0",
      committedProfile:
        profile && Number(profile.score) > 0
          ? {
              score: profile.score,
              riskTier: profile.riskTier,
              confidenceBps: Number(profile.confidenceBps),
              modelId: profile.modelId as `0x${string}`,
              reasonsHash: profile.reasonsHash as `0x${string}`,
              evidenceHash: profile.evidenceHash as `0x${string}`,
              lastUpdated: profile.lastUpdated,
            }
          : null,
      liveEval: liveEval
        ? {
            score: liveEval.score,
            tier: liveEval.tier,
            confidenceBps: Number(liveEval.confidenceBps),
            modelId: liveEval.modelId,
            reasonCodes: liveEval.reasonCodes,
            evidence: liveEval.evidence,
          }
        : null,
      attestationsLatest: attestationsForPanel.map((a) => ({
        attestationType: a.label,
        attestationId: a.attestationId,
        data: a.data,
        uri: a.uri,
        issuer: a.issuer,
        issuedAt: a.issuedAt,
        expiresAt: a.expiresAt,
        valid: a.valid,
        revoked: a.revoked,
      })),
    });

  if (!dealId) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-12">
        <p className="text-neutral-500">Invalid deal ID. Use 0x + 64 hex.</p>
        <Link href="/deals" className="mt-4 block text-emerald-500 hover:underline">
          ← Deals
        </Link>
      </main>
    );
  }

  if (deal && deal.sponsor === ZERO) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-12">
        <p className="text-neutral-500">Deal not found.</p>
        <Link href="/deals" className="mt-4 block text-emerald-500 hover:underline">
          ← Deals
        </Link>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-3xl px-4 py-12">
      <header className="mb-10 flex items-center justify-between">
        <Link href="/deals" className="text-neutral-500 hover:text-neutral-300">
          ← Deals
        </Link>
        <ConnectButton />
      </header>

      {deal && (
        <>
          <DealHeader deal={deal} />
          <div className="mt-6 flex flex-wrap gap-2">
            <UnderwritingPacketExportButton
              buildPacket={buildPacket}
              dealIdShort={dealId.slice(0, 10)}
            />
          </div>
          <div className="mt-6 grid gap-6">
            <DealMetadataPanel deal={deal} onUpdated={refetchDeal} />
            <DealUnderwritingPanel dealId={dealId} onCommitted={refetchProfile} />
            <DealAttestationsPanel dealId={dealId} attestations={attestationsForPanel} />
            <DealCapitalStackPanel buildPacket={buildPacket} />
          </div>
        </>
      )}

      {!deal && hasFactory && (
        <p className="text-neutral-500">Loading deal…</p>
      )}
    </main>
  );
}
