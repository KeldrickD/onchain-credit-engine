import test from "node:test";
import assert from "node:assert/strict";

import {
  buildRiskPayloadV2,
  buildRiskPayloadV2ByKey,
  hashEvidence,
  hashReasons,
  riskOracleDomain,
  riskPayloadV2TypedData,
  riskPayloadV2ByKeyTypedData,
} from "../dist/index.js";

const MODEL_ID = "0x1111111111111111111111111111111111111111111111111111111111111111";
const USER = "0x1234567890123456789012345678901234567890";
const SUBJECT_KEY = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const REASONS = [
  "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
];
const EVIDENCE = [
  "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
];

test("buildRiskPayloadV2 hashes reason and evidence arrays", () => {
  const payload = buildRiskPayloadV2({
    user: USER,
    score: 712,
    riskTier: 2,
    confidenceBps: 7800,
    modelId: MODEL_ID,
    reasonCodes: REASONS,
    evidence: EVIDENCE,
    timestamp: 1000n,
    nonce: 7n,
  });

  assert.equal(payload.reasonsHash, hashReasons(REASONS));
  assert.equal(payload.evidenceHash, hashEvidence(EVIDENCE));
});

test("wallet and subject typed data helpers keep expected primary types", () => {
  const domain = riskOracleDomain(
    84532,
    "0xffffffffffffffffffffffffffffffffffffffff"
  );

  const walletTypedData = riskPayloadV2TypedData(
    domain,
    buildRiskPayloadV2({
      user: USER,
      score: 712,
      riskTier: 2,
      confidenceBps: 7800,
      modelId: MODEL_ID,
      reasonCodes: REASONS,
      evidence: EVIDENCE,
      timestamp: 1000n,
      nonce: 7n,
    })
  );

  const keyedTypedData = riskPayloadV2ByKeyTypedData(
    domain,
    buildRiskPayloadV2ByKey({
      subjectKey: SUBJECT_KEY,
      score: 712,
      riskTier: 2,
      confidenceBps: 7800,
      modelId: MODEL_ID,
      reasonCodes: REASONS,
      evidence: EVIDENCE,
      timestamp: 1000n,
      nonce: 7n,
    })
  );

  assert.equal(walletTypedData.primaryType, "RiskPayloadV2");
  assert.equal(keyedTypedData.primaryType, "RiskPayloadV2ByKey");
  assert.equal(walletTypedData.message.user, USER);
  assert.equal(keyedTypedData.message.subjectKey, SUBJECT_KEY);
});
