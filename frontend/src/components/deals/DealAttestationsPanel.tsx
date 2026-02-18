"use client";

import Link from "next/link";
import { useReadContracts } from "wagmi";
import { keccak256 } from "viem";
import { attestationRegistryAbi } from "@/abi/attestationRegistry";
import { contractAddresses } from "@/lib/contracts";
import { ValueRow } from "./ValueRow";

const ZERO = "0x0000000000000000000000000000000000000000";

const COMMON_TYPES = [
  "DSCR_BPS",
  "NOI_USD6",
  "KYB_PASS",
  "SPONSOR_TRACK",
].map((label) => ({ label, hash: keccak256(new TextEncoder().encode(label)) as `0x${string}` }));

function isZero(a: string) {
  return !a || a === ZERO;
}

export type AttestationRow = {
  label: string;
  attestationId: string;
  data: string;
  uri: string;
  issuer: string;
  issuedAt: number;
  expiresAt: number;
  valid: boolean;
  revoked: boolean;
};

type DealAttestationsPanelProps = {
  dealId: `0x${string}`;
  /** When provided, panel renders this list and does not fetch (used by detail page for export) */
  attestations?: AttestationRow[];
};

export function DealAttestationsPanel({ dealId, attestations: attestationsProp }: DealAttestationsPanelProps) {
  const hasRegistry = !isZero(contractAddresses.attestationRegistry);

  const idCalls = COMMON_TYPES.map(({ hash }) => ({
    address: contractAddresses.attestationRegistry,
    abi: attestationRegistryAbi,
    functionName: "getLatestSubjectAttestationId" as const,
    args: [dealId, hash],
  }));

  const { data: idResults } = useReadContracts({
    contracts: hasRegistry && !attestationsProp ? idCalls : [],
  });

  const attestationIds = (idResults ?? []).map((r) => {
    if (r.status !== "success" || !r.result) return null;
    const id = r.result as `0x${string}`;
    return id === "0x0000000000000000000000000000000000000000000000000000000000000000" ? null : id;
  });

  const fetchCalls =
    attestationsProp && attestationsProp.length > 0
      ? []
      : attestationIds
          .filter((id): id is `0x${string}` => id != null)
          .map((id) => ({
              address: contractAddresses.attestationRegistry,
              abi: attestationRegistryAbi,
              functionName: "getSubjectAttestation" as const,
              args: [id],
            }));

  const { data: attResults } = useReadContracts({
    contracts: fetchCalls.length > 0 ? fetchCalls : [],
  });

  if (attestationsProp && attestationsProp.length > 0) {
    return (
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-medium text-neutral-400">Attestations (latest by type)</h3>
          <Link href="/admin/underwriting" className="text-sm text-emerald-500 hover:underline">
            Add attestations →
          </Link>
        </div>
        <ul className="space-y-3">
          {attestationsProp.map((item, i) => (
            <li key={i} className="rounded-lg border border-neutral-700/50 p-3">
              <div className="flex items-center gap-2">
                <span className="font-mono text-sm text-neutral-300">{item.label}</span>
                <span
                  className={`rounded px-1.5 py-0.5 text-xs ${
                    item.valid ? "bg-emerald-900/40 text-emerald-400" : "bg-amber-900/40 text-amber-400"
                  }`}
                >
                  {item.valid ? "Valid" : item.revoked ? "Revoked" : "Expired"}
                </span>
              </div>
              <ValueRow label="Data" value={item.data} mono />
              {item.uri && <ValueRow label="URI" value={item.uri} mono />}
              <ValueRow label="Issuer" value={`${item.issuer.slice(0, 10)}…`} mono />
              <ValueRow
                label="Issued"
                value={item.issuedAt ? new Date(item.issuedAt * 1000).toISOString().slice(0, 16) : "—"}
              />
              {item.expiresAt > 0 && (
                <ValueRow label="Expires" value={new Date(item.expiresAt * 1000).toISOString().slice(0, 16)} />
              )}
            </li>
          ))}
        </ul>
      </div>
    );
  }

  const nonNullIds = attestationIds.filter((id): id is `0x${string}` => id != null);
  const list = COMMON_TYPES.map(({ label }, i) => {
    const id = attestationIds[i];
    if (id == null) return { label, data: "", uri: "", issuer: "", issuedAt: 0, expiresAt: 0, valid: false, revoked: false };
    const k = nonNullIds.indexOf(id);
    const r = attResults?.[k];
    const tuple = r?.status === "success" && r?.result ? (r.result as [unknown, boolean, boolean]) : null;
    const att = tuple ? (tuple[0] as { data?: bigint | string; uri?: string; issuedAt?: bigint; expiresAt?: bigint; issuer?: `0x${string}` }) : null;
    const revoked = tuple ? tuple[1] : false;
    const expired = tuple ? tuple[2] : false;
    return {
      label,
      data: att?.data != null ? String(att.data) : "",
      uri: att?.uri ?? "",
      issuer: att?.issuer ?? "",
      issuedAt: att?.issuedAt != null ? Number(att.issuedAt) : 0,
      expiresAt: att?.expiresAt != null ? Number(att.expiresAt) : 0,
      valid: !revoked && !expired,
      revoked,
    };
  }).filter((x) => x.data !== "" || x.uri !== "" || x.issuedAt > 0);

  return (
    <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-sm font-medium text-neutral-400">Attestations (latest by type)</h3>
        <Link
          href="/admin/underwriting"
          className="text-sm text-emerald-500 hover:underline"
        >
          Add attestations →
        </Link>
      </div>
      {!hasRegistry && (
        <p className="text-sm text-neutral-500">Attestation registry not configured.</p>
      )}
      {hasRegistry && list.length === 0 && (
        <p className="text-sm text-neutral-500">No subject attestations yet. Add them in Underwriting.</p>
      )}
      {list.length > 0 && (
        <ul className="space-y-3">
          {list.map((item, i) => (
            <li key={i} className="rounded-lg border border-neutral-700/50 p-3">
              <div className="flex items-center gap-2">
                <span className="font-mono text-sm text-neutral-300">{item.label}</span>
                <span
                  className={`rounded px-1.5 py-0.5 text-xs ${
                    item.valid ? "bg-emerald-900/40 text-emerald-400" : "bg-amber-900/40 text-amber-400"
                  }`}
                >
                  {item.valid ? "Valid" : item.revoked ? "Revoked" : "Expired"}
                </span>
              </div>
              <ValueRow label="Data" value={item.data} mono />
              {item.uri && <ValueRow label="URI" value={item.uri} mono />}
              <ValueRow label="Issuer" value={`${item.issuer.slice(0, 10)}…`} mono />
              <ValueRow
                label="Issued"
                value={item.issuedAt ? new Date(item.issuedAt * 1000).toISOString().slice(0, 16) : "—"}
              />
              {item.expiresAt > 0 && (
                <ValueRow
                  label="Expires"
                  value={new Date(item.expiresAt * 1000).toISOString().slice(0, 16)}
                />
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
