"use client";

import Link from "next/link";
import { ConnectButton } from "@/components/ConnectButton";
import { DealCreateForm } from "@/components/deals/DealCreateForm";

export default function DealsCreatePage() {
  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <header className="mb-10 flex items-center justify-between">
        <Link href="/deals" className="text-neutral-500 hover:text-neutral-300">
          ← Deals
        </Link>
        <ConnectButton />
      </header>
      <h1 className="mb-2 text-2xl font-bold">Create deal</h1>
      <p className="mb-6 text-neutral-500">
        Register a first-class deal subject (sponsor, type, metadata, requested capital).
      </p>
      <DealCreateForm />
    </main>
  );
}
