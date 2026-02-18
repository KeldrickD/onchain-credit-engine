"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useReadContract } from "wagmi";
import { keccak256, type Hex } from "viem";
import toast, { Toaster } from "react-hot-toast";
import { ConnectButton } from "@/components/ConnectButton";
import { TxButton } from "@/components/admin/TxButton";
import { contractAddresses, adminAddress } from "@/lib/contracts";
import {
  fetchAttestationSignature,
  fetchSubjectAttestationSignature,
} from "@/lib/api";
import { attestationRegistryAbi } from "@/abi/attestationRegistry";

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

function isZero(addr: `0x${string}` | null) {
  return !addr || addr === ZERO;
}

const ATTESTATION_TYPES = [
  { label: "NOI_USD6", value: "NOI_USD6" },
  { label: "DSCR_BPS", value: "DSCR_BPS" },
  { label: "KYB_PASS", value: "KYB_PASS" },
  { label: "SPONSOR_TRACK", value: "SPONSOR_TRACK" },
  { label: "Custom (hex)", value: "__custom__" },
];

export default function UnderwritingPage() {
  const { address, isConnected } = useAccount();
  const isAdmin =
    !!address &&
    !!adminAddress &&
    address.toLowerCase() === adminAddress.toLowerCase();

  const [subject, setSubject] = useState("");
  const [subjectMode, setSubjectMode] = useState<"wallet" | "subjectId">("wallet");
  const [attestationType, setAttestationType] = useState("NOI_USD6");
  const [customTypeHex, setCustomTypeHex] = useState("");
  const [dataInput, setDataInput] = useState("");
  const [dataValue, setDataValue] = useState("");
  const [uri, setUri] = useState("");
  const [expiresAt, setExpiresAt] = useState("");

  const hasRegistry = !isZero(contractAddresses.attestationRegistry);

  const subjectAddr =
    subject.trim().startsWith("0x") && subject.trim().length === 42
      ? (subject.trim() as `0x${string}`)
      : undefined;
  const subjectIdHex =
    subject.trim().startsWith("0x") && subject.trim().length === 66
      ? (subject.trim() as `0x${string}`)
      : undefined;
  const { data: nextWalletNonce } = useReadContract({
    address: hasRegistry ? contractAddresses.attestationRegistry : undefined,
    abi: attestationRegistryAbi,
    functionName: "nextNonce",
    args: subjectMode === "wallet" && subjectAddr ? [subjectAddr] : undefined,
  });
  const { data: nextSubjectNonce } = useReadContract({
    address: hasRegistry ? contractAddresses.attestationRegistry : undefined,
    abi: attestationRegistryAbi,
    functionName: "nextSubjectNonce",
    args: subjectMode === "subjectId" && subjectIdHex ? [subjectIdHex] : undefined,
  });

  const dataHash: Hex | undefined = dataInput.trim()
    ? dataInput.startsWith("0x") && dataInput.length === 66
      ? (dataInput as Hex)
      : (keccak256(new TextEncoder().encode(dataInput)) as Hex)
    : undefined;

  const {
    writeContract: writeSubmit,
    data: submitHash,
    isPending: submitPending,
    reset: resetSubmit,
    error: submitError,
  } = useWriteContract();

  const { status: submitStatus } = useWaitForTransactionReceipt({
    hash: submitHash,
  });

  useEffect(() => {
    if (submitStatus === "success") {
      toast.dismiss();
      toast.success("Attestation submitted");
      resetSubmit();
      setDataInput("");
      setSubject("");
    } else if (submitStatus === "error") {
      toast.dismiss();
      toast.error("Submit failed");
      resetSubmit();
    }
  }, [submitStatus, resetSubmit]);

  const handleSubmit = async () => {
    if (!subject || !dataHash || !hasRegistry) {
      toast.error("Enter subject and data, ensure registry is configured");
      return;
    }
    const subj = subject.trim();
    const isWalletMode = subjectMode === "wallet";
    if (isWalletMode && (!subj.startsWith("0x") || subj.length !== 42)) {
      toast.error("Subject wallet must be a valid address (0x...)");
      return;
    }
    if (!isWalletMode && (!subj.startsWith("0x") || subj.length !== 66)) {
      toast.error("SubjectId must be bytes32 (0x + 64 hex)");
      return;
    }
    const typeVal =
      attestationType === "__custom__" ? (customTypeHex.startsWith("0x") ? customTypeHex : `0x${customTypeHex}`) : attestationType;
    if (!typeVal) {
      toast.error("Select or enter attestation type");
      return;
    }
    try {
      toast.loading("Signing attestation…");
      const dataForBackend = dataValue.trim() || undefined;
      const expiresAtSeconds = expiresAt
        ? String(Math.floor(parseInt(expiresAt, 10) / 1000))
        : undefined;
      toast.dismiss();
      toast.loading("Submitting tx…");
      if (isWalletMode) {
        const { payload, signature } = await fetchAttestationSignature(
          subj,
          typeVal,
          dataHash as string,
          uri || undefined,
          expiresAtSeconds,
          dataForBackend
        );
        const att = {
          subject: payload.subject as `0x${string}`,
          attestationType: payload.attestationType as `0x${string}`,
          dataHash: payload.dataHash as `0x${string}`,
          data: (payload.data ||
            "0x0000000000000000000000000000000000000000000000000000000000000000") as `0x${string}`,
          uri: payload.uri,
          issuedAt: BigInt(payload.issuedAt),
          expiresAt: BigInt(payload.expiresAt),
          nonce: BigInt(payload.nonce),
        };
        writeSubmit({
          address: contractAddresses.attestationRegistry,
          abi: attestationRegistryAbi,
          functionName: "submitAttestation",
          args: [att, signature],
        });
      } else {
        const { payload, signature } = await fetchSubjectAttestationSignature(
          subj,
          typeVal,
          dataHash as string,
          uri || undefined,
          expiresAtSeconds,
          dataForBackend
        );
        const att = {
          subjectId: payload.subjectId as `0x${string}`,
          attestationType: payload.attestationType as `0x${string}`,
          dataHash: payload.dataHash as `0x${string}`,
          data: (payload.data ||
            "0x0000000000000000000000000000000000000000000000000000000000000000") as `0x${string}`,
          uri: payload.uri,
          issuedAt: BigInt(payload.issuedAt),
          expiresAt: BigInt(payload.expiresAt),
          nonce: BigInt(payload.nonce),
        };
        writeSubmit({
          address: contractAddresses.attestationRegistry,
          abi: attestationRegistryAbi,
          functionName: "submitSubjectAttestation",
          args: [att, signature],
        });
      }
    } catch (e) {
      toast.dismiss();
      toast.error((e as Error).message);
    }
  };

  const baseSepoliaExplorer = "https://sepolia.basescan.org";

  const adminContent = (
    <div className="space-y-6">
      {!hasRegistry && (
        <div className="rounded-xl border border-amber-900/50 bg-amber-950/20 p-4">
          <p className="text-amber-600">AttestationRegistry address not configured</p>
          <p className="mt-1 text-sm text-neutral-500">
            Set NEXT_PUBLIC_ATTESTATION_REGISTRY_ADDRESS in .env.local
          </p>
        </div>
      )}

      <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        <h2 className="mb-4 text-lg font-semibold">Submit Attestation</h2>
        <p className="mb-4 text-sm text-neutral-500">
          Underwriters with ISSUER_ROLE sign via backend. Backend must have ATTESTATION_REGISTRY_ADDRESS
          and ATTESTATION_SIGNER_PRIVATE_KEY. Grant ISSUER_ROLE to the signer.
        </p>
        <div className="space-y-4">
          <div>
            <label className="mb-1 block text-sm text-neutral-500">Subject mode</label>
            <select
              value={subjectMode}
              onChange={(e) => setSubjectMode(e.target.value as "wallet" | "subjectId")}
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm"
            >
              <option value="wallet">Wallet address</option>
              <option value="subjectId">Subject ID (bytes32)</option>
            </select>
          </div>
          <div>
            <label className="mb-1 block text-sm text-neutral-500">
              {subjectMode === "wallet" ? "Subject wallet (address)" : "Subject ID (bytes32)"}
            </label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder={subjectMode === "wallet" ? "0x..." : "0x<64 hex>"}
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
            />
            {(subjectMode === "wallet" ? nextWalletNonce : nextSubjectNonce) !== undefined && (
              <p className="mt-1 text-xs text-neutral-500">
                Next nonce: {String(subjectMode === "wallet" ? nextWalletNonce : nextSubjectNonce)}
              </p>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm text-neutral-500">Attestation type</label>
            <select
              value={attestationType}
              onChange={(e) => setAttestationType(e.target.value)}
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm"
            >
              {ATTESTATION_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
            {attestationType === "__custom__" && (
              <input
                type="text"
                value={customTypeHex}
                onChange={(e) => setCustomTypeHex(e.target.value)}
                placeholder="0x... (32 bytes)"
                className="mt-2 w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
              />
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm text-neutral-500">
              Data (string or 0x hex → keccak256) or dataHash (0x + 64 hex)
            </label>
            <input
              type="text"
              value={dataInput}
              onChange={(e) => setDataInput(e.target.value)}
              placeholder="12345 or 0x..."
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm text-neutral-500">
              Data value (numeric, e.g. 13000 for DSCR 1.30; 0 = presence-only)
            </label>
            <input
              type="text"
              value={dataValue}
              onChange={(e) => setDataValue(e.target.value)}
              placeholder="13000 for DSCR_BPS"
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm text-neutral-500">URI (optional, e.g. ipfs://)</label>
            <input
              type="text"
              value={uri}
              onChange={(e) => setUri(e.target.value)}
              placeholder="ipfs://..."
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm text-neutral-500">
              Expires at (optional, Unix timestamp ms, 0 = no expiry)
            </label>
            <input
              type="text"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
              placeholder="0"
              className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
            />
          </div>
          <TxButton
            onClick={handleSubmit}
            pending={submitPending}
            pendingLabel="Submitting…"
            disabled={!hasRegistry || !subject || !dataInput || !dataHash}
          >
            Submit {subjectMode === "wallet" ? "wallet" : "subject"} attestation
          </TxButton>
          {submitHash && (
            <a
              href={`${baseSepoliaExplorer}/tx/${submitHash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="block text-sm text-emerald-500 hover:underline"
            >
              View tx →
            </a>
          )}
          {submitError && (
            <p className="text-sm text-red-400">{submitError.message}</p>
          )}
        </div>
      </section>

      <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        <h2 className="mb-2 text-lg font-semibold">View attestations</h2>
        <p className="text-sm text-neutral-500">
          Use getLatest/getAttestation for wallet subjects, or getLatestSubject/getSubjectAttestation
          for Subject IDs.
        </p>
      </section>
    </div>
  );

  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <Toaster position="top-right" />
      <header className="mb-10 flex items-center justify-between">
        <div className="flex gap-4">
          <Link href="/admin" className="text-neutral-500 hover:text-neutral-300">
            ← Admin
          </Link>
        </div>
        <ConnectButton />
      </header>

      <h1 className="mb-2 text-2xl font-bold">Underwriting</h1>
      <p className="mb-6 text-neutral-500">
        Submit attestations (NOI, DSCR, KYB, etc.) for RiskEngine v2
      </p>

      {!isConnected ? (
        <p className="text-neutral-500">Connect wallet to continue.</p>
      ) : !isAdmin ? (
        <p className="text-amber-600">
          Admin address required for underwriting. Connect with NEXT_PUBLIC_ADMIN_ADDRESS.
        </p>
      ) : (
        adminContent
      )}
    </main>
  );
}
