# OCX Integration Personas

OCX adoption inside a protocol team usually involves three roles.

Each role evaluates the system from a different perspective.
Successful integrations address all three.

---

# 1. Protocol Engineer

### Goal

Integrate deterministic credit gating without introducing fragile infrastructure.

### What they care about

- simple contract reads
- deterministic behavior
- minimal new infrastructure
- env-driven configuration
- ability to self-host if needed

### What OCX provides

- deterministic evaluation spec
- simple read surface such as `CreditRegistry.getProfile`
- SDK helpers for reading profiles and applying policies
- optional hosted evaluator for quick integration
- ability to run your own signer and registry deployment

### Minimal integration

Most protocols integrate OCX with a simple credit gate:

```ts
const profile = await readWalletProfile(client, wallet)

const PASS =
  profile.score >= 650 &&
  profile.riskTier <= 2 &&
  profile.confidenceBps >= 6000

if (!PASS) throw new Error("OCX credit gate failed")
```

Typical integration size: **20-40 lines of code**

---

# 2. Risk / Underwriting Owner

### Goal

Define safe decision rules for lending, onboarding, or pricing.

### What they care about

- explainable scoring outputs
- freshness of evaluations
- confidence levels
- policy thresholds they can justify

### What OCX provides

OCX profiles contain:

- `score`
- `riskTier`
- `confidenceBps`
- a signed payload timestamp or equivalent freshness signal

Protocols translate these into policy rules.

### Reference policy

`PASS`

- `score >= 700`
- `riskTier <= 2`
- `confidenceBps >= 6000`
- profile age `<= 7 days`

`REVIEW`

- `score` between `600-699`
- `confidenceBps` between `4000-6000`
- profile age `<= 30 days`

`BLOCK`

- `score < 600`
- `confidenceBps < 4000`
- profile age `> 30 days`

Protocols should adjust thresholds based on risk tolerance.

OCX provides **the profile format**, not the policy.

---

# 3. Protocol Lead / Product / BD

### Goal

Improve lending safety or underwriting quality without rebuilding risk infrastructure.

### What they care about

- fast integration
- low operational overhead
- ability to adopt incrementally

### What OCX provides

Protocols can adopt OCX in stages:

`Stage 1`

Read profiles and apply a simple gate.

`Stage 2`

Adjust pricing or collateral requirements using tiers.

`Stage 3`

Integrate subject-key profiles for deal-level underwriting.

No protocol changes to collateral or liquidation logic are required.

---

# Summary

OCX separates responsibilities cleanly:

- `OCX = profile format + evaluation spec`
- `registry = deployment`
- `issuers = signal providers`
- `protocols = policy owners`
