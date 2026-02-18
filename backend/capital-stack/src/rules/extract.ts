/**
 * Extract stack inputs from underwriting packet (or use provided inputs).
 * DSCR_BPS: value in bps (e.g. 13000 = 1.30). NOI_USD6, KYB_PASS, SPONSOR_TRACK by type.
 */

import type { UnderwritingPacketV0, StackInputs, ExtractedInputs } from "../types.js";

const DSCR_BPS = "DSCR_BPS";
const NOI_USD6 = "NOI_USD6";
const KYB_PASS = "KYB_PASS";
const SPONSOR_TRACK = "SPONSOR_TRACK";

export function extractFromPacket(packet: UnderwritingPacketV0): ExtractedInputs {
  const committed = packet.creditProfileCommitted;
  const live = packet.riskEngineLive;
  const profile = committed ?? live;
  const tier = profile ? profile.tier : 0;
  const score = profile ? profile.score : 0;
  const confidenceBps = profile ? profile.confidenceBps : 0;

  let dscrBps: number | undefined;
  let noiPresent = false;
  let kybPass = false;
  let sponsorTrack = false;

  for (const a of packet.attestationsLatest) {
    const t = (a.attestationType || "").toUpperCase();
    if (t === DSCR_BPS && a.data) {
      const n = parseInt(a.data, 10);
      if (!Number.isNaN(n)) dscrBps = n;
    } else if (t === NOI_USD6 && a.data) {
      noiPresent = true;
    } else if (t === KYB_PASS) {
      kybPass = true;
    } else if (t === SPONSOR_TRACK) {
      sponsorTrack = true;
    }
  }

  return {
    requestedUSDC6: packet.deal.requestedUSDC6,
    tier,
    score,
    confidenceBps,
    dscrBps,
    noiPresent,
    kybPass,
    sponsorTrack,
    flags: { kybPass, sponsorTrack, noiPresent },
  };
}

export function toStackInputs(extracted: ExtractedInputs): StackInputs {
  return {
    requestedUSDC6: extracted.requestedUSDC6,
    tier: extracted.tier,
    score: extracted.score,
    confidenceBps: extracted.confidenceBps,
    dscrBps: extracted.dscrBps,
    noiPresent: extracted.noiPresent,
    kybPass: extracted.kybPass,
    sponsorTrack: extracted.sponsorTrack,
  };
}
