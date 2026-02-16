"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useReadContract } from "wagmi";
import { parseUnits, formatUnits } from "viem";
import toast, { Toaster } from "react-hot-toast";
import { ConnectButton } from "@/components/ConnectButton";
import { AdminGuard } from "@/components/admin/AdminGuard";
import { AssetSelector } from "@/components/admin/AssetSelector";
import { KeyValueRow } from "@/components/admin/KeyValueRow";
import { TxButton } from "@/components/admin/TxButton";
import {
  contractAddresses,
  adminAddress,
  oracleSignerUrl,
} from "@/lib/contracts";
import { checkOracleSignerHealth, fetchPriceSignature } from "@/lib/api";
import { priceRouterAbi } from "@/abi/priceRouter";
import { collateralManagerAbi } from "@/abi/collateralManager";

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

function isZero(addr: `0x${string}` | null) {
  return !addr || addr === ZERO;
}

const SOURCE_LABELS: Record<number, string> = {
  0: "NONE",
  1: "CHAINLINK",
  2: "SIGNED",
};

type OracleHealth = { ok: boolean; configured?: boolean } | null;

export default function AdminPage() {
  const { address, isConnected } = useAccount();
  const isAdmin =
    !!address &&
    !!adminAddress &&
    address.toLowerCase() === adminAddress.toLowerCase();

  const [asset, setAsset] = useState<`0x${string}` | null>(null);
  const [health, setHealth] = useState<OracleHealth>(null);

  const hasAddrs =
    !isZero(contractAddresses.priceRouter) &&
    !isZero(contractAddresses.collateralManager);

  const { data: priceData, refetch: refetchPrice } = useReadContract({
    address: hasAddrs ? contractAddresses.priceRouter : undefined,
    abi: priceRouterAbi,
    functionName: "getPriceUSD8",
    args: asset ? [asset] : undefined,
  });

  const { data: source } = useReadContract({
    address: hasAddrs ? contractAddresses.priceRouter : undefined,
    abi: priceRouterAbi,
    functionName: "getSource",
    args: asset ? [asset] : undefined,
  });

  const { data: stalePeriod } = useReadContract({
    address: hasAddrs ? contractAddresses.priceRouter : undefined,
    abi: priceRouterAbi,
    functionName: "getStalePeriod",
    args: asset ? [asset] : undefined,
  });

  const { data: chainlinkFeed } = useReadContract({
    address: hasAddrs ? contractAddresses.priceRouter : undefined,
    abi: priceRouterAbi,
    functionName: "getChainlinkFeed",
    args: asset ? [asset] : undefined,
  });

  const { data: signedOracle } = useReadContract({
    address: hasAddrs ? contractAddresses.priceRouter : undefined,
    abi: priceRouterAbi,
    functionName: "getSignedOracle",
    args: asset ? [asset] : undefined,
  });

  const { data: collateralConfig } = useReadContract({
    address: hasAddrs ? contractAddresses.collateralManager : undefined,
    abi: collateralManagerAbi,
    functionName: "getConfig",
    args: asset ? [asset] : undefined,
  });

  const { data: totalDebt } = useReadContract({
    address: hasAddrs ? contractAddresses.collateralManager : undefined,
    abi: collateralManagerAbi,
    functionName: "totalDebtUSDC6",
    args: asset ? [asset] : undefined,
  });

  useEffect(() => {
    let cancelled = false;
    checkOracleSignerHealth()
      .then((h) => {
        if (!cancelled) setHealth(h);
      })
      .catch(() => {
        if (!cancelled) setHealth({ ok: false });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const [priceInput, setPriceInput] = useState("");
  const [collEnabled, setCollEnabled] = useState(true);
  const [haircutBps, setHaircutBps] = useState("10000");
  const [ltvBpsCap, setLtvBpsCap] = useState("8000");
  const [liqBpsCap, setLiqBpsCap] = useState("8800");
  const [debtCeiling, setDebtCeiling] = useState("500000");
  const [routerSource, setRouterSource] = useState<"0" | "1" | "2">("1");
  const [chainlinkFeedInput, setChainlinkFeedInput] = useState("");
  const [stalePeriodInput, setStalePeriodInput] = useState("3600");
  const [signedOracleInput, setSignedOracleInput] = useState("");

  useEffect(() => {
    if (collateralConfig) {
      setCollEnabled(collateralConfig.enabled);
      setHaircutBps(String(collateralConfig.haircutBps));
      setLtvBpsCap(String(collateralConfig.ltvBpsCap));
      setLiqBpsCap(collateralConfig.liquidationThresholdBpsCap === 0 ? "" : String(collateralConfig.liquidationThresholdBpsCap));
      setDebtCeiling(formatUnits(collateralConfig.debtCeilingUSDC6, 6));
    }
  }, [collateralConfig]);

  useEffect(() => {
    if (source !== undefined) setRouterSource(String(source) as "0" | "1" | "2");
  }, [source]);

  useEffect(() => {
    if (chainlinkFeed && chainlinkFeed !== ZERO) setChainlinkFeedInput(chainlinkFeed);
  }, [chainlinkFeed]);

  useEffect(() => {
    if (stalePeriod !== undefined) setStalePeriodInput(String(stalePeriod));
  }, [stalePeriod]);

  useEffect(() => {
    if (signedOracle && signedOracle !== ZERO) setSignedOracleInput(signedOracle);
  }, [signedOracle]);

  useEffect(() => {
    if (!asset && !isZero(contractAddresses.weth)) {
      setAsset(contractAddresses.weth);
    }
  }, [contractAddresses.weth]);

  const priceUSD8 = priceData?.[0];
  const updatedAt = priceData?.[1];
  const isStale = priceData?.[2] === true;

  const {
    writeContract: writeUpdatePrice,
    data: updatePriceHash,
    isPending: updatePricePending,
    reset: resetUpdatePrice,
    error: updatePriceError,
  } = useWriteContract();

  const {
    writeContract: writeSetConfig,
    data: setConfigHash,
    isPending: setConfigPending,
    reset: resetSetConfig,
    error: setConfigError,
  } = useWriteContract();

  const {
    writeContract: writeSetSource,
    data: setSourceHash,
    isPending: setSourcePending,
    reset: resetSetSource,
  } = useWriteContract();

  const {
    writeContract: writeSetFeed,
    data: setFeedHash,
    isPending: setFeedPending,
    reset: resetSetFeed,
  } = useWriteContract();

  const {
    writeContract: writeSetStalePeriod,
    data: setStalePeriodHash,
    isPending: setStalePeriodPending,
    reset: resetSetStalePeriod,
  } = useWriteContract();

  const {
    writeContract: writeSetSignedOracle,
    data: setSignedOracleHash,
    isPending: setSignedOraclePending,
    reset: resetSetSignedOracle,
  } = useWriteContract();

  const { status: updatePriceStatus } = useWaitForTransactionReceipt({
    hash: updatePriceHash,
  });
  useEffect(() => {
    if (updatePriceStatus === "success") {
      toast.dismiss();
      toast.success("Price updated");
      resetUpdatePrice();
      refetchPrice();
    } else if (updatePriceStatus === "error") {
      toast.dismiss();
      toast.error("Price update failed");
      resetUpdatePrice();
    }
  }, [updatePriceStatus, resetUpdatePrice, refetchPrice]);

  const { status: setConfigStatus } = useWaitForTransactionReceipt({
    hash: setConfigHash,
  });
  useEffect(() => {
    if (setConfigStatus === "success") {
      toast.success("Collateral config saved");
      resetSetConfig();
    } else if (setConfigStatus === "error") {
      toast.error("Save config failed");
      resetSetConfig();
    }
  }, [setConfigStatus, resetSetConfig]);

  const { status: setSourceStatus } = useWaitForTransactionReceipt({
    hash: setSourceHash,
  });
  useEffect(() => {
    if (setSourceStatus === "success") {
      toast.success("Source updated");
      resetSetSource();
    } else if (setSourceStatus === "error") {
      toast.error("Set source failed");
      resetSetSource();
    }
  }, [setSourceStatus, resetSetSource]);

  const { status: setFeedStatus } = useWaitForTransactionReceipt({
    hash: setFeedHash,
  });
  useEffect(() => {
    if (setFeedStatus === "success") {
      toast.success("Chainlink feed set");
      resetSetFeed();
    } else if (setFeedStatus === "error") {
      toast.error("Set feed failed");
      resetSetFeed();
    }
  }, [setFeedStatus, resetSetFeed]);

  const { status: setStalePeriodStatus } = useWaitForTransactionReceipt({
    hash: setStalePeriodHash,
  });
  useEffect(() => {
    if (setStalePeriodStatus === "success") {
      toast.success("Stale period set");
      resetSetStalePeriod();
    } else if (setStalePeriodStatus === "error") {
      toast.error("Set stale period failed");
      resetSetStalePeriod();
    }
  }, [setStalePeriodStatus, resetSetStalePeriod]);

  const { status: setSignedOracleStatus } = useWaitForTransactionReceipt({
    hash: setSignedOracleHash,
  });
  useEffect(() => {
    if (setSignedOracleStatus === "success") {
      toast.success("Signed oracle set");
      resetSetSignedOracle();
    } else if (setSignedOracleStatus === "error") {
      toast.error("Set signed oracle failed");
      resetSetSignedOracle();
    }
  }, [setSignedOracleStatus, resetSetSignedOracle]);

  const handlePriceUpdate = async () => {
    if (!asset || !priceInput || !health?.ok) {
      if (!health?.ok) toast.error("Oracle signer unhealthy");
      else toast.error("Enter asset and price");
      return;
    }
    const priceUSD8Big = parseUnits(priceInput, 8);
    if (priceUSD8Big <= 0n) {
      toast.error("Price must be > 0");
      return;
    }
    const src = source as number | undefined;
    if (src !== 2) {
      toast("Router source is not SIGNED — update may fail. Consider setting source to SIGNED first.", {
        icon: "⚠️",
      });
    }
    try {
      toast.loading("Signing…");
      const { payload, signature } = await fetchPriceSignature(
        asset,
        priceUSD8Big.toString()
      );
      toast.dismiss();
      toast.loading("Submitting tx…");
      const pricePayload = {
        asset: payload.asset as `0x${string}`,
        price: BigInt(payload.price),
        timestamp: BigInt(payload.timestamp),
        nonce: BigInt(payload.nonce),
      };
      writeUpdatePrice({
        address: contractAddresses.priceRouter,
        abi: priceRouterAbi,
        functionName: "updateSignedPriceAndGet",
        args: [asset, pricePayload, signature],
      });
    } catch (e) {
      toast.dismiss();
      toast.error((e as Error).message);
    }
  };

  const handleSaveCollateralConfig = () => {
    if (!asset || !hasAddrs) {
      toast.error("Select asset");
      return;
    }
    const haircut = parseInt(haircutBps, 10);
    const ltv = parseInt(ltvBpsCap, 10);
    const liq = liqBpsCap.trim() ? parseInt(liqBpsCap, 10) : 0;
    if (isNaN(haircut) || haircut < 0 || haircut > 10000) {
      toast.error("Haircut must be 0–10000");
      return;
    }
    if (isNaN(ltv) || ltv < 0 || ltv > 10000) {
      toast.error("LTV must be 0–10000");
      return;
    }
    if (liq !== 0 && (isNaN(liq) || liq < 0 || liq > 10000)) {
      toast.error("Liquidation threshold must be 0–10000 or empty");
      return;
    }
    if (liq !== 0 && ltv > liq) {
      toast.error("LTV cannot exceed liquidation threshold");
      return;
    }
    const ceiling = parseUnits(debtCeiling || "0", 6);
    writeSetConfig({
      address: contractAddresses.collateralManager,
      abi: collateralManagerAbi,
      functionName: "setConfig",
      args: [
        asset,
        {
          enabled: collEnabled,
          ltvBpsCap: ltv as number,
          liquidationThresholdBpsCap: liq as number,
          haircutBps: haircut as number,
          debtCeilingUSDC6: ceiling,
        },
      ],
    });
  };

  const handleSetSource = () => {
    if (!asset) {
      toast.error("Select asset");
      return;
    }
    writeSetSource({
      address: contractAddresses.priceRouter,
      abi: priceRouterAbi,
      functionName: "setSource",
      args: [asset, parseInt(routerSource, 10) as 0 | 1 | 2],
    });
  };

  const handleSetFeed = () => {
    if (!asset) {
      toast.error("Select asset");
      return;
    }
    const feed = chainlinkFeedInput.trim() as `0x${string}`;
    if (!feed || feed.length < 42) {
      toast.error("Enter valid feed address");
      return;
    }
    writeSetFeed({
      address: contractAddresses.priceRouter,
      abi: priceRouterAbi,
      functionName: "setChainlinkFeed",
      args: [asset, feed],
    });
  };

  const handleSetStalePeriod = () => {
    if (!asset) {
      toast.error("Select asset");
      return;
    }
    const sec = parseInt(stalePeriodInput, 10);
    if (isNaN(sec) || sec < 0) {
      toast.error("Enter valid stale period (seconds)");
      return;
    }
    writeSetStalePeriod({
      address: contractAddresses.priceRouter,
      abi: priceRouterAbi,
      functionName: "setStalePeriod",
      args: [asset, BigInt(sec)],
    });
  };

  const handleSetSignedOracle = () => {
    if (!asset) {
      toast.error("Select asset");
      return;
    }
    const oracle = signedOracleInput.trim() as `0x${string}`;
    if (!oracle || oracle.length < 42) {
      toast.error("Enter valid oracle address");
      return;
    }
    writeSetSignedOracle({
      address: contractAddresses.priceRouter,
      abi: priceRouterAbi,
      functionName: "setSignedOracle",
      args: [asset, oracle],
    });
  };

  const baseSepoliaExplorer = "https://sepolia.basescan.org";
  const txLink = (hash: `0x${string}` | undefined) =>
    hash ? `${baseSepoliaExplorer}/tx/${hash}` : null;

  const readOnlyContent = (
    <div className="space-y-6">
      <Section1SystemStatus
        asset={asset}
        setAsset={setAsset}
        hasAddrs={hasAddrs}
        health={health}
        priceUSD8={priceUSD8}
        updatedAt={updatedAt}
        isStale={isStale}
        source={source}
        chainlinkFeed={chainlinkFeed}
        signedOracle={signedOracle}
        stalePeriod={stalePeriod}
      />
    </div>
  );

  const adminContent = (
    <div className="space-y-6">
      <Section1SystemStatus
        asset={asset}
        setAsset={setAsset}
        hasAddrs={hasAddrs}
        health={health}
        priceUSD8={priceUSD8}
        updatedAt={updatedAt}
        isStale={isStale}
        source={source}
        chainlinkFeed={chainlinkFeed}
        signedOracle={signedOracle}
        stalePeriod={stalePeriod}
      />

      {isAdmin && asset && (
        <>
          <Section2PriceUpdates
            asset={asset}
            source={source}
            health={health}
            priceInput={priceInput}
            setPriceInput={setPriceInput}
            onUpdate={handlePriceUpdate}
            pending={updatePricePending}
            txHash={updatePriceHash}
            txLink={txLink}
            error={updatePriceError}
          />

          <Section3CollateralConfig
            asset={asset}
            collateralConfig={collateralConfig}
            totalDebt={totalDebt}
            collEnabled={collEnabled}
            setCollEnabled={setCollEnabled}
            haircutBps={haircutBps}
            setHaircutBps={setHaircutBps}
            ltvBpsCap={ltvBpsCap}
            setLtvBpsCap={setLtvBpsCap}
            liqBpsCap={liqBpsCap}
            setLiqBpsCap={setLiqBpsCap}
            debtCeiling={debtCeiling}
            setDebtCeiling={setDebtCeiling}
            onSave={handleSaveCollateralConfig}
            pending={setConfigPending}
            txHash={setConfigHash}
            txLink={txLink}
            error={setConfigError}
          />

          <Section4RouterConfig
            asset={asset}
            source={source}
            chainlinkFeed={chainlinkFeed}
            signedOracle={signedOracle}
            signedOracleInput={signedOracleInput}
            setSignedOracleInput={setSignedOracleInput}
            onSetSignedOracle={handleSetSignedOracle}
            setSignedOraclePending={setSignedOraclePending}
            setSignedOracleHash={setSignedOracleHash}
            routerSource={routerSource}
            setRouterSource={setRouterSource}
            chainlinkFeedInput={chainlinkFeedInput}
            setChainlinkFeedInput={setChainlinkFeedInput}
            stalePeriodInput={stalePeriodInput}
            setStalePeriodInput={setStalePeriodInput}
            onSetSource={handleSetSource}
            onSetFeed={handleSetFeed}
            onSetStalePeriod={handleSetStalePeriod}
            setSourcePending={setSourcePending}
            setFeedPending={setFeedPending}
            setStalePeriodPending={setStalePeriodPending}
            setSourceHash={setSourceHash}
            setFeedHash={setFeedHash}
            setStalePeriodHash={setStalePeriodHash}
            txLink={txLink}
          />
        </>
      )}
    </div>
  );

  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <Toaster position="top-right" />
      <header className="mb-10 flex items-center justify-between">
        <Link href="/" className="text-neutral-500 hover:text-neutral-300">
          ← Dashboard
        </Link>
        <ConnectButton />
      </header>

      <h1 className="mb-2 text-2xl font-bold">Admin</h1>
      <p className="mb-6 text-neutral-500">
        System status, price updates, collateral config, router config
      </p>
      <Link
        href="/admin/underwriting"
        className="mb-4 inline-block rounded-lg bg-neutral-800 px-4 py-2 text-sm font-medium text-neutral-200 hover:bg-neutral-700"
      >
        Underwriting →
      </Link>

      {!hasAddrs && (
        <div className="mb-6 rounded-xl border border-amber-900/50 bg-amber-950/20 p-4">
          <p className="text-amber-600">Contract addresses not configured</p>
          <p className="mt-1 text-sm text-neutral-500">
            Set NEXT_PUBLIC_PRICE_ROUTER_ADDRESS, NEXT_PUBLIC_COLLATERAL_MANAGER_ADDRESS, etc. in
            .env.local
          </p>
        </div>
      )}

      <AdminGuard
        isAdmin={!!isAdmin}
        isConnected={!!isConnected}
        adminOnlyContent={adminContent}
        readOnlyContent={readOnlyContent}
        notConnectedContent={
          <p className="text-neutral-500">Connect wallet to view admin.</p>
        }
      />
    </main>
  );
}

function Section1SystemStatus({
  asset,
  setAsset,
  hasAddrs,
  health,
  priceUSD8,
  updatedAt,
  isStale,
  source,
  chainlinkFeed,
  signedOracle,
  stalePeriod,
}: {
  asset: `0x${string}` | null;
  setAsset: (a: `0x${string}` | null) => void;
  hasAddrs: boolean;
  health: OracleHealth;
  priceUSD8: bigint | undefined;
  updatedAt: bigint | undefined;
  isStale: boolean;
  source: unknown;
  chainlinkFeed: `0x${string}` | undefined;
  signedOracle: `0x${string}` | undefined;
  stalePeriod: bigint | undefined;
}) {
  const src = source as number | undefined;
  const srcLabel = src !== undefined ? SOURCE_LABELS[src] ?? "?" : "—";

  return (
    <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h2 className="mb-4 text-lg font-semibold">1. System Status</h2>
      {!hasAddrs ? (
        <p className="text-neutral-500">Configure contract addresses first.</p>
      ) : (
        <div className="space-y-4">
          <div>
            <label className="mb-2 block text-sm text-neutral-500">Asset</label>
            <AssetSelector value={asset} onChange={setAsset} />
          </div>

          <div className="space-y-1">
            <KeyValueRow label="Oracle signer" value={health?.ok ? "✓ OK" : health === null ? "Checking…" : "✗ Unhealthy"} />
            {health?.configured !== undefined && (
              <KeyValueRow label="Configured" value={health.configured ? "Yes" : "No"} />
            )}
            <KeyValueRow label="Signer URL" value={oracleSignerUrl} />
          </div>

          <div className="space-y-1 rounded-lg border border-neutral-700/50 p-3">
            <p className="text-sm font-medium text-neutral-400">Addresses</p>
            <KeyValueRow label="Router" value={contractAddresses.priceRouter?.slice(0, 10) + "…"} />
            <KeyValueRow label="CollateralManager" value={contractAddresses.collateralManager?.slice(0, 10) + "…"} />
            <KeyValueRow label="LoanEngine" value={contractAddresses.loanEngine?.slice(0, 10) + "…"} />
            <KeyValueRow label="Vault" value={contractAddresses.treasuryVault?.slice(0, 10) + "…"} />
          </div>

          <div className="flex flex-wrap gap-2">
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                src === 2 ? "bg-emerald-900/50 text-emerald-400" : "bg-neutral-700 text-neutral-300"
              }`}
            >
              {srcLabel}
            </span>
            {isStale && <span className="rounded-full bg-amber-900/50 px-2 py-0.5 text-xs font-medium text-amber-500">STALE</span>}
            {!isStale && priceUSD8 !== undefined && priceUSD8 > 0n && (
              <span className="rounded-full bg-emerald-900/50 px-2 py-0.5 text-xs font-medium text-emerald-400">OK</span>
            )}
            {priceUSD8 === 0n && src !== 0 && (
              <span className="rounded-full bg-red-900/50 px-2 py-0.5 text-xs font-medium text-red-400">NO FEED</span>
            )}
          </div>

          <KeyValueRow
            label="Price (USD8)"
            value={priceUSD8 !== undefined ? formatUnits(priceUSD8, 8) : "—"}
          />
          <KeyValueRow
            label="Updated at"
            value={
              updatedAt !== undefined && updatedAt > 0n
                ? new Date(Number(updatedAt) * 1000).toISOString()
                : "—"
            }
          />
          <KeyValueRow label="Source" value={srcLabel} />
          <KeyValueRow
            label="Chainlink feed"
            value={chainlinkFeed && chainlinkFeed !== ZERO ? chainlinkFeed.slice(0, 12) + "…" : "—"}
          />
          <KeyValueRow
            label="Signed oracle"
            value={signedOracle && signedOracle !== ZERO ? signedOracle.slice(0, 12) + "…" : "—"}
          />
          <KeyValueRow label="Stale period (s)" value={stalePeriod !== undefined ? String(stalePeriod) : "—"} />
        </div>
      )}
    </section>
  );
}

function Section2PriceUpdates({
  asset,
  source,
  health,
  priceInput,
  setPriceInput,
  onUpdate,
  pending,
  txHash,
  txLink,
  error,
}: {
  asset: `0x${string}`;
  source: unknown;
  health: OracleHealth;
  priceInput: string;
  setPriceInput: (v: string) => void;
  onUpdate: () => void;
  pending: boolean;
  txHash: `0x${string}` | undefined;
  txLink: (h: `0x${string}` | undefined) => string | null;
  error: Error | null;
}) {
  const src = source as number | undefined;
  const isSigned = src === 2;

  return (
    <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h2 className="mb-4 text-lg font-semibold">2. Price Updates (SIGNED)</h2>
      {!isSigned && (
        <p className="mb-3 text-amber-600 text-sm">
          Router source is not SIGNED. Set source to SIGNED in Router Config first, or updates may fail.
        </p>
      )}
      {!health?.ok && (
        <p className="mb-3 text-amber-600 text-sm">Oracle signer unhealthy. Blocking price updates.</p>
      )}
      <div className="space-y-4">
        <div>
          <label className="mb-1 block text-sm text-neutral-500">Price (human, e.g. 2500.12)</label>
          <input
            type="text"
            value={priceInput}
            onChange={(e) => setPriceInput(e.target.value)}
            placeholder="2500.12"
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
          />
        </div>
        <TxButton
          onClick={onUpdate}
          pending={pending}
          pendingLabel="Submitting…"
          disabled={!health?.ok || !priceInput}
        >
          Update signed price
        </TxButton>
        {txHash && (
          <a
            href={txLink(txHash) ?? "#"}
            target="_blank"
            rel="noopener noreferrer"
            className="block text-sm text-emerald-500 hover:underline"
          >
            View tx →
          </a>
        )}
        {error && <p className="text-sm text-red-400">{error.message}</p>}
      </div>
    </section>
  );
}

function Section3CollateralConfig({
  asset,
  collateralConfig,
  totalDebt,
  collEnabled,
  setCollEnabled,
  haircutBps,
  setHaircutBps,
  ltvBpsCap,
  setLtvBpsCap,
  liqBpsCap,
  setLiqBpsCap,
  debtCeiling,
  setDebtCeiling,
  onSave,
  pending,
  txHash,
  txLink,
  error,
}: {
  asset: `0x${string}`;
  collateralConfig: unknown;
  totalDebt: bigint | undefined;
  collEnabled: boolean;
  setCollEnabled: (v: boolean) => void;
  haircutBps: string;
  setHaircutBps: (v: string) => void;
  ltvBpsCap: string;
  setLtvBpsCap: (v: string) => void;
  liqBpsCap: string;
  setLiqBpsCap: (v: string) => void;
  debtCeiling: string;
  setDebtCeiling: (v: string) => void;
  onSave: () => void;
  pending: boolean;
  txHash: `0x${string}` | undefined;
  txLink: (h: `0x${string}` | undefined) => string | null;
  error: Error | null;
}) {
  const cfg = collateralConfig as
    | { debtCeilingUSDC6: bigint }
    | undefined;
  const ceiling = cfg?.debtCeilingUSDC6 ?? 0n;
  const debt = totalDebt ?? 0n;
  const remaining = ceiling > 0n ? ceiling - debt : null;

  return (
    <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h2 className="mb-4 text-lg font-semibold">3. Collateral Risk Config</h2>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="collEnabled"
            checked={collEnabled}
            onChange={(e) => setCollEnabled(e.target.checked)}
            className="rounded border-neutral-600"
          />
          <label htmlFor="collEnabled" className="text-sm">enabled</label>
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">haircutBps (0–10000)</label>
          <input
            type="text"
            value={haircutBps}
            onChange={(e) => setHaircutBps(e.target.value)}
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">ltvBpsCap (0–10000)</label>
          <input
            type="text"
            value={ltvBpsCap}
            onChange={(e) => setLtvBpsCap(e.target.value)}
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">liquidationThresholdBpsCap (0 or 0–10000)</label>
          <input
            type="text"
            value={liqBpsCap}
            onChange={(e) => setLiqBpsCap(e.target.value)}
            placeholder="8800 or empty for no cap"
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">debtCeilingUSDC6</label>
          <input
            type="text"
            value={debtCeiling}
            onChange={(e) => setDebtCeiling(e.target.value)}
            placeholder="500000"
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono"
          />
        </div>
        <TxButton onClick={onSave} pending={pending} pendingLabel="Saving…">
          Save config
        </TxButton>
        {txHash && (
          <a
            href={txLink(txHash) ?? "#"}
            target="_blank"
            rel="noopener noreferrer"
            className="block text-sm text-emerald-500 hover:underline"
          >
            View tx →
          </a>
        )}
        {error && <p className="text-sm text-red-400">{error.message}</p>}
      </div>
      {cfg != null && (
        <div className="mt-4 space-y-1 rounded-lg border border-neutral-700/50 p-3">
          <p className="text-sm font-medium text-neutral-400">Current</p>
          <KeyValueRow label="totalDebt" value={formatUnits(debt, 6) + " USDC"} />
          {remaining !== null && (
            <KeyValueRow label="remaining ceiling" value={formatUnits(remaining, 6) + " USDC"} />
          )}
        </div>
      )}
    </section>
  );
}

function Section4RouterConfig({
  asset,
  source,
  chainlinkFeed,
  signedOracle,
  signedOracleInput,
  setSignedOracleInput,
  onSetSignedOracle,
  setSignedOraclePending,
  setSignedOracleHash,
  routerSource,
  setRouterSource,
  chainlinkFeedInput,
  setChainlinkFeedInput,
  stalePeriodInput,
  setStalePeriodInput,
  onSetSource,
  onSetFeed,
  onSetStalePeriod,
  setSourcePending,
  setFeedPending,
  setStalePeriodPending,
  setSourceHash,
  setFeedHash,
  setStalePeriodHash,
  txLink,
}: {
  asset: `0x${string}`;
  source: unknown;
  chainlinkFeed: `0x${string}` | undefined;
  signedOracle: `0x${string}` | undefined;
  signedOracleInput: string;
  setSignedOracleInput: (v: string) => void;
  onSetSignedOracle: () => void;
  setSignedOraclePending: boolean;
  setSignedOracleHash: `0x${string}` | undefined;
  routerSource: string;
  setRouterSource: (v: "0" | "1" | "2") => void;
  chainlinkFeedInput: string;
  setChainlinkFeedInput: (v: string) => void;
  stalePeriodInput: string;
  setStalePeriodInput: (v: string) => void;
  onSetSource: () => void;
  onSetFeed: () => void;
  onSetStalePeriod: () => void;
  setSourcePending: boolean;
  setFeedPending: boolean;
  setStalePeriodPending: boolean;
  setSourceHash: `0x${string}` | undefined;
  setFeedHash: `0x${string}` | undefined;
  setStalePeriodHash: `0x${string}` | undefined;
  txLink: (h: `0x${string}` | undefined) => string | null;
}) {
  const src = source as number | undefined;
  const noFeed = src === 1 && (!chainlinkFeed || chainlinkFeed === ZERO);
  const signedNoOracle = src === 2 && (!signedOracle || signedOracle === ZERO);

  return (
    <section className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
      <h2 className="mb-4 text-lg font-semibold">4. Router Config</h2>
      {noFeed && (
        <p className="mb-3 text-amber-600 text-sm">CHAINLINK source but no feed set.</p>
      )}
      {signedNoOracle && (
        <p className="mb-3 text-amber-600 text-sm">SIGNED source but no signed oracle configured.</p>
      )}
      <div className="space-y-4">
        <div>
          <label className="mb-2 block text-sm text-neutral-500">Source</label>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setRouterSource("0")}
              className={`rounded-lg px-3 py-1.5 text-sm ${routerSource === "0" ? "bg-neutral-600" : "bg-neutral-800"}`}
            >
              NONE
            </button>
            <button
              type="button"
              onClick={() => setRouterSource("1")}
              className={`rounded-lg px-3 py-1.5 text-sm ${routerSource === "1" ? "bg-neutral-600" : "bg-neutral-800"}`}
            >
              CHAINLINK
            </button>
            <button
              type="button"
              onClick={() => setRouterSource("2")}
              className={`rounded-lg px-3 py-1.5 text-sm ${routerSource === "2" ? "bg-neutral-600" : "bg-neutral-800"}`}
            >
              SIGNED
            </button>
          </div>
          <TxButton onClick={onSetSource} pending={setSourcePending} className="mt-2 rounded-lg bg-neutral-600 px-3 py-1.5 text-sm">
            Set source
          </TxButton>
          {setSourceHash && (
            <a href={txLink(setSourceHash) ?? "#"} target="_blank" rel="noopener noreferrer" className="ml-2 text-sm text-emerald-500">
              View tx →
            </a>
          )}
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">Chainlink feed address</label>
          <input
            type="text"
            value={chainlinkFeedInput}
            onChange={(e) => setChainlinkFeedInput(e.target.value)}
            placeholder="0x..."
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
          />
          <TxButton onClick={onSetFeed} pending={setFeedPending} className="mt-2 rounded-lg bg-neutral-600 px-3 py-1.5 text-sm">
            Set feed
          </TxButton>
          {setFeedHash && (
            <a href={txLink(setFeedHash) ?? "#"} target="_blank" rel="noopener noreferrer" className="ml-2 text-sm text-emerald-500">
              View tx →
            </a>
          )}
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">Signed oracle address</label>
          <input
            type="text"
            value={signedOracleInput}
            onChange={(e) => setSignedOracleInput(e.target.value)}
            placeholder="0x..."
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
          />
          <TxButton onClick={onSetSignedOracle} pending={setSignedOraclePending} className="mt-2 rounded-lg bg-neutral-600 px-3 py-1.5 text-sm">
            Set signed oracle
          </TxButton>
          {setSignedOracleHash && (
            <a href={txLink(setSignedOracleHash) ?? "#"} target="_blank" rel="noopener noreferrer" className="ml-2 text-sm text-emerald-500">
              View tx →
            </a>
          )}
        </div>
        <div>
          <label className="mb-1 block text-sm text-neutral-500">Stale period (seconds)</label>
          <input
            type="text"
            value={stalePeriodInput}
            onChange={(e) => setStalePeriodInput(e.target.value)}
            className="w-full rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 font-mono text-sm"
          />
          <TxButton onClick={onSetStalePeriod} pending={setStalePeriodPending} className="mt-2 rounded-lg bg-neutral-600 px-3 py-1.5 text-sm">
            Set stale period
          </TxButton>
          {setStalePeriodHash && (
            <a href={txLink(setStalePeriodHash) ?? "#"} target="_blank" rel="noopener noreferrer" className="ml-2 text-sm text-emerald-500">
              View tx →
            </a>
          )}
        </div>
      </div>
    </section>
  );
}
