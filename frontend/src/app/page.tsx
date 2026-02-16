import Link from "next/link";
import { ConnectButton } from "@/components/ConnectButton";
import { Dashboard } from "@/components/Dashboard";

export default function Home() {
  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <header className="mb-10 flex items-center justify-between">
        <h1 className="text-2xl font-bold tracking-tight">OCX</h1>
        <ConnectButton />
      </header>

      <p className="mb-6 text-neutral-500">
        Onchain Credit Engine — Dashboard
      </p>

      <nav className="mb-8 flex gap-4">
        <Link
          href="/borrow"
          className="rounded-lg bg-neutral-800 px-4 py-2 text-sm font-medium text-neutral-200 hover:bg-neutral-700"
        >
          Borrow
        </Link>
        <Link
          href="/repay"
          className="rounded-lg bg-neutral-800 px-4 py-2 text-sm font-medium text-neutral-200 hover:bg-neutral-700"
        >
          Repay
        </Link>
        <Link
          href="/risk"
          className="rounded-lg bg-neutral-800 px-4 py-2 text-sm font-medium text-neutral-200 hover:bg-neutral-700"
        >
          Risk
        </Link>
        <Link
          href="/admin"
          className="rounded-lg bg-neutral-800 px-4 py-2 text-sm font-medium text-neutral-200 hover:bg-neutral-700"
        >
          Admin
        </Link>
      </nav>

      <Dashboard />
    </main>
  );
}
