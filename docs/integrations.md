# OCX Integrations

OCX is a composable credit state protocol designed for lending, underwriting, and RWA platforms.

If you're building a protocol that needs:

- onchain credit scoring
- underwriting infrastructure
- attestation pipelines
- subject-key risk profiles for deals, SPVs, and pools
- deterministic risk evaluation

OCX can plug into your stack through a self-hosted signer flow or a hosted evaluation path that returns signed payloads ready for onchain commit.

## Typical engagements

- Protocol architecture
- Credit evaluation pipelines
- Attestation issuer integrations
- Risk engine customization
- Onchain credit gating

## Hosted Evaluation API

Phase 1 includes a hosted evaluator inside the oracle signer service.

### Wallet lane

`POST /risk/evaluate`

```json
{
  "user": "0x1234567890123456789012345678901234567890",
  "kyb": true,
  "dscr": 1.7,
  "noi": 125000,
  "sponsorScore": 720
}
```

### Subject lane

`POST /risk/evaluate-subject`

```json
{
  "subjectId": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "kyb": true,
  "dscr": 1.7,
  "noi": 125000,
  "sponsorScore": 720
}
```

Both routes return a signed OCX-compatible payload with:

- `score`
- `tier`
- `confidenceBps`
- `reasonsHash`
- `evidenceHash`
- `payload`
- `signature`

That payload can be committed through `updateCreditProfileV2()` or `updateCreditProfileV2ByKey()`.

## Phase 1 scoring policy

The hosted evaluator uses a deterministic scoring model intended for fast integrations and commercial pilots.

- Base score: `480`
- `kyb === true`: `+60`
- DSCR:
  - `>= 1.75`: `+80`
  - `>= 1.35`: `+55`
  - `>= 1.00`: `+25`
- NOI:
  - `>= 250,000`: `+70`
  - `>= 100,000`: `+45`
  - `>= 50,000`: `+20`
- Sponsor score:
  - `>= 760`: `+75`
  - `>= 720`: `+55`
  - `>= 680`: `+30`

### Tier bands

- Tier 0: `score >= 780`
- Tier 1: `score >= 720`
- Tier 2: `score >= 660`
- Tier 3: `score >= 580`
- Tier 4: `score >= 500`
- Tier 5: below `500`

### Confidence bands

- Base confidence: `5000 bps`
- Confidence increases as validated inputs are present and stronger.
- Output is clamped to `4000-9500 bps`.

Reason codes and evidence entries are emitted deterministically and hashed into `reasonsHash` and `evidenceHash`.

## Pricing

| Plan | Price | Fit |
|------|-------|-----|
| Developer | Free | Test integrations and local evaluation flows |
| Startup | $199/mo | Early teams that want hosted evaluation and support |
| Protocol | $1,500/mo | Production integrations with custom thresholds or flows |
| Enterprise | Custom | Multi-product deployments, custom infra, or advisory |

The model is simple on purpose: credit infrastructure as a service.

## Contact

For integrations, pilots, or custom credit infrastructure work:

**keldrickddev@gmail.com**
