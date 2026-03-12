import Link from "next/link";

const pricing = [
  { name: "Developer", price: "Free", detail: "Test integrations and local evaluation flows." },
  { name: "Startup", price: "$199/mo", detail: "Hosted evaluation and lightweight integration support." },
  { name: "Protocol", price: "$1,500/mo", detail: "Production integration support and custom credit flows." },
  { name: "Enterprise", price: "Custom", detail: "Multi-team deployments, advisory, and deeper infra design." },
];

const offerings = [
  "Onchain credit scoring",
  "Underwriting infrastructure",
  "Attestation pipelines",
  "Subject-key risk profiles",
  "Deterministic risk evaluation",
];

export default function IntegrationsPage() {
  return (
    <main className="min-h-screen bg-stone-950 text-stone-100">
      <section className="mx-auto flex max-w-6xl flex-col gap-12 px-6 py-16 sm:px-10 lg:px-12">
        <div className="flex flex-col gap-6 lg:max-w-3xl">
          <p className="text-sm uppercase tracking-[0.35em] text-amber-300">OCX Integrations</p>
          <h1 className="text-4xl font-semibold tracking-tight text-stone-50 sm:text-6xl">
            Credit infrastructure for teams shipping lending, underwriting, and RWA products.
          </h1>
          <p className="max-w-2xl text-lg leading-8 text-stone-300">
            OCX is a composable credit state protocol built for protocols that need a deterministic,
            signed risk layer without spending months building custom underwriting rails first.
          </p>
          <div className="flex flex-wrap gap-3 text-sm text-stone-200">
            <a
              href="mailto:keldrickddev@gmail.com"
              className="rounded-full bg-amber-300 px-5 py-3 font-medium text-stone-950 transition hover:bg-amber-200"
            >
              Email keldrickddev@gmail.com
            </a>
            <Link
              href="/"
              className="rounded-full border border-stone-700 px-5 py-3 font-medium text-stone-200 transition hover:border-stone-500 hover:text-stone-50"
            >
              Back to dashboard
            </Link>
          </div>
        </div>

        <div className="grid gap-6 lg:grid-cols-[1.15fr_0.85fr]">
          <div className="rounded-[2rem] border border-stone-800 bg-stone-900/80 p-8 shadow-2xl shadow-black/30">
            <h2 className="text-2xl font-semibold text-stone-50">What teams use OCX for</h2>
            <div className="mt-6 grid gap-3 sm:grid-cols-2">
              {offerings.map((item) => (
                <div key={item} className="rounded-2xl border border-stone-800 bg-stone-950/70 p-4 text-stone-200">
                  {item}
                </div>
              ))}
            </div>
            <div className="mt-8 rounded-3xl border border-emerald-900/60 bg-emerald-950/30 p-6">
              <p className="text-sm uppercase tracking-[0.3em] text-emerald-300">Hosted Evaluation API</p>
              <p className="mt-3 text-stone-200">
                Start with the hosted path for speed, then move to self-hosted signer infrastructure when
                trust minimization matters. Both lanes return signed OCX-compatible payloads.
              </p>
              <div className="mt-4 grid gap-3 text-sm text-stone-300 sm:grid-cols-2">
                <div className="rounded-2xl border border-emerald-900/50 bg-stone-950/60 p-4">
                  <p className="font-medium text-stone-100">Wallet lane</p>
                  <p className="mt-2 font-mono text-xs text-emerald-300">POST /risk/evaluate</p>
                </div>
                <div className="rounded-2xl border border-emerald-900/50 bg-stone-950/60 p-4">
                  <p className="font-medium text-stone-100">Subject lane</p>
                  <p className="mt-2 font-mono text-xs text-emerald-300">POST /risk/evaluate-subject</p>
                </div>
              </div>
            </div>
          </div>

          <div className="rounded-[2rem] border border-stone-800 bg-gradient-to-b from-stone-900 to-stone-950 p-8">
            <p className="text-sm uppercase tracking-[0.3em] text-rose-300">Pricing</p>
            <div className="mt-6 space-y-4">
              {pricing.map((tier) => (
                <div key={tier.name} className="rounded-3xl border border-stone-800 bg-stone-950/80 p-5">
                  <div className="flex items-baseline justify-between gap-4">
                    <h2 className="text-xl font-semibold text-stone-50">{tier.name}</h2>
                    <span className="text-lg font-medium text-amber-300">{tier.price}</span>
                  </div>
                  <p className="mt-3 text-sm leading-6 text-stone-300">{tier.detail}</p>
                </div>
              ))}
            </div>
            <div className="mt-8 rounded-3xl border border-stone-800 bg-stone-900/70 p-5 text-sm text-stone-300">
              <p className="font-medium text-stone-100">Typical engagements</p>
              <ul className="mt-3 space-y-2">
                <li>Protocol architecture</li>
                <li>Credit evaluation pipelines</li>
                <li>Attestation issuer integrations</li>
                <li>Risk engine customization</li>
                <li>Onchain credit gating</li>
              </ul>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
