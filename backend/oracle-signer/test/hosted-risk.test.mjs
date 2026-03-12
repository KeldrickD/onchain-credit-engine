import test from "node:test";
import assert from "node:assert/strict";

import { evaluateHostedRisk, hashHexArray } from "../dist/hosted-risk.js";

test("hosted risk evaluation is deterministic for identical inputs", () => {
  const inputs = { kyb: true, dscr: 1.7, noi: 125000, sponsorScore: 720 };
  const a = evaluateHostedRisk(inputs);
  const b = evaluateHostedRisk(inputs);

  assert.deepEqual(a, b);
  assert.equal(a.score, 695);
  assert.equal(a.tier, 2);
  assert.equal(a.confidenceBps, 8850);
  assert.equal(hashHexArray(a.reasonCodes), hashHexArray(b.reasonCodes));
  assert.equal(hashHexArray(a.evidence), hashHexArray(b.evidence));
});

test("hosted risk scoring improves as inputs strengthen", () => {
  const weaker = evaluateHostedRisk({ kyb: false, dscr: 1.0, noi: 50000, sponsorScore: 680 });
  const stronger = evaluateHostedRisk({ kyb: true, dscr: 1.9, noi: 250000, sponsorScore: 760 });

  assert.ok(stronger.score > weaker.score);
  assert.ok(stronger.confidenceBps > weaker.confidenceBps);
  assert.ok(stronger.tier < weaker.tier);
});
