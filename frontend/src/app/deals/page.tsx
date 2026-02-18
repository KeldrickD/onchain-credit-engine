"use client";

import Link from "next/link";
import { ConnectButton } from "@/components/ConnectButton";
import { DealList } from "@/components/deals/DealList";

export default function DealsPage() {
  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <header className="mb-10 flex items-center justify-between">
        <Link href="/" className="text-neutral-500 hover:text-neutral-300">
          ← Dashboard
        </Link>
        <ConnectButton />
      </header>
      <div className="mb-6 flex items-center gap-4">
        <h1 className="text-2xl font-bold">Deals</h1>
        <Link
          href="/deals/create"
          className="rounded-lg bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-500"
        >
          Create deal
        </Link>
      </div>
      <p className="mb-6 text-neutral-500">
        List of deals you track. Create a deal or add a deal ID below.
      </p>
      <DealList />
    </main>
  );
}
