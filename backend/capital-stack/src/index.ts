/**
 * Capital stack suggestion: deterministic stack + pricing from underwriting packet.
 * Exports suggestResponse() and a Fastify plugin for POST /capital-stack/suggest.
 */

import type { FastifyInstance, FastifyPluginOptions } from "fastify";
import { extractFromPacket } from "./rules/extract.js";
import { suggestStack, suggestPricing } from "./rules/suggest.js";
import { buildRationale, buildConstraints, buildSensitivity } from "./explain/rationale.js";
import type {
  CapitalStackSuggestRequest,
  CapitalStackSuggestResponse,
  UnderwritingPacketV0,
  StackInputs,
  Overrides,
  ExtractedInputs,
} from "./types.js";

function parseRequest(body: unknown): { inputs: ExtractedInputs; overrides?: Overrides; dealId?: string } {
  const req = body as CapitalStackSuggestRequest;
  if (!req || (typeof req !== "object")) {
    throw new Error("Missing request body");
  }

  let inputs: ExtractedInputs;
  let dealId: string | undefined;

  if ("packet" in req && req.packet) {
    const packet = req.packet as UnderwritingPacketV0;
    inputs = extractFromPacket(packet);
    dealId = packet.deal?.dealId;
  } else if ("inputs" in req && req.inputs) {
    const in_ = req.inputs as StackInputs;
    inputs = {
      ...in_,
      flags: {
        kybPass: in_.kybPass ?? false,
        sponsorTrack: in_.sponsorTrack ?? false,
        noiPresent: in_.noiPresent ?? false,
      },
    };
  } else {
    throw new Error("Provide either { packet } or { inputs }");
  }

  return { inputs, overrides: req.overrides, dealId };
}

function toUSDC6(requested: string, pct: number): string {
  const total = BigInt(requested);
  const pctScaled = Math.round(pct * 100);
  return ((total * BigInt(pctScaled)) / 10000n).toString();
}

export function suggestResponse(
  inputs: ExtractedInputs,
  overrides?: Overrides
): CapitalStackSuggestResponse {
  const stack = suggestStack(inputs, overrides);
  const pricing = suggestPricing(inputs, stack);
  const requestedUSDC6 = inputs.requestedUSDC6;
  const rationale = buildRationale(inputs, stack);
  const constraints = buildConstraints(stack);
  const sensitivity = buildSensitivity();

  return {
    version: "capital-stack/v0",
    requestedUSDC6,
    inputs: {
      tier: inputs.tier,
      score: inputs.score,
      confidenceBps: inputs.confidenceBps,
      dscrBps: inputs.dscrBps,
      flags: inputs.flags,
    },
    stack: {
      seniorPct: Math.round(stack.senior * 100) / 100,
      mezzPct: Math.round(stack.mezz * 100) / 100,
      prefPct: Math.round(stack.pref * 100) / 100,
      commonPct: Math.round(stack.common * 100) / 100,
      seniorUSDC6: toUSDC6(requestedUSDC6, stack.senior),
      mezzUSDC6: toUSDC6(requestedUSDC6, stack.mezz),
      prefUSDC6: toUSDC6(requestedUSDC6, stack.pref),
      commonUSDC6: toUSDC6(requestedUSDC6, stack.common),
    },
    pricing: {
      seniorAprBps: pricing.seniorAprBps,
      mezzAprBps: pricing.mezzAprBps,
      prefReturnBps: pricing.prefReturnBps,
    },
    constraints,
    rationale,
    sensitivity,
  };
}

export async function capitalStackPlugin(
  fastify: FastifyInstance,
  _opts: FastifyPluginOptions
): Promise<void> {
  fastify.post<{ Body: unknown }>("/capital-stack/suggest", async (req, reply) => {
    try {
      const { inputs, overrides, dealId } = parseRequest(req.body);
      const response = suggestResponse(inputs, overrides);
      if (dealId) response.dealId = dealId;
      return response;
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Invalid request";
      return reply.status(400).send({ error: msg });
    }
  });
}
