import Fastify from "fastify";
import cors from "@fastify/cors";
import {
  createPublicClient,
  createWalletClient,
  encodeAbiParameters,
  http,
  keccak256,
  type Hash,
  type Hex,
} from "viem";
import { baseSepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

const PORT = parseInt(process.env.PORT ?? "3001", 10);
const RPC_URL = process.env.RPC_URL ?? "https://sepolia.base.org";
const CHAIN_ID = parseInt(process.env.CHAIN_ID ?? "84532", 10);
const RISK_ORACLE = (process.env.RISK_ORACLE_ADDRESS ?? "") as Hex;
const PRICE_ORACLE = (process.env.SIGNED_PRICE_ORACLE_ADDRESS ?? "") as Hex;
const ATTESTATION_REGISTRY = (process.env.ATTESTATION_REGISTRY_ADDRESS ?? "") as Hex;
const RISK_ENGINE_V2 = (process.env.RISK_ENGINE_V2_ADDRESS ?? "") as Hex;
const EXPECTED_RISK_MODEL_ID = (process.env.EXPECTED_RISK_MODEL_ID ?? "") as Hex;
const RISK_KEY = process.env.RISK_SIGNER_PRIVATE_KEY as Hex | undefined;
const PRICE_KEY = process.env.PRICE_SIGNER_PRIVATE_KEY as Hex | undefined;
const ATTESTATION_KEY = process.env.ATTESTATION_SIGNER_PRIVATE_KEY as Hex | undefined;

const riskOracleAbi = [
  {
    inputs: [{ name: "user", type: "address" }],
    name: "nextNonce",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        components: [
          { name: "user", type: "address" },
          { name: "score", type: "uint16" },
          { name: "riskTier", type: "uint8" },
          { name: "confidenceBps", type: "uint16" },
          { name: "modelId", type: "bytes32" },
          { name: "reasonsHash", type: "bytes32" },
          { name: "evidenceHash", type: "bytes32" },
          { name: "timestamp", type: "uint64" },
          { name: "nonce", type: "uint64" },
        ],
        name: "payload",
        type: "tuple",
      },
    ],
    name: "getPayloadDigestV2",
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        components: [
          { name: "user", type: "address" },
          { name: "score", type: "uint256" },
          { name: "riskTier", type: "uint256" },
          { name: "timestamp", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
        name: "payload",
        type: "tuple",
      },
    ],
    name: "getPayloadDigest",
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "subjectKey", type: "bytes32" }],
    name: "nextNonceKey",
    outputs: [{ name: "", type: "uint64" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        components: [
          { name: "subjectKey", type: "bytes32" },
          { name: "score", type: "uint16" },
          { name: "riskTier", type: "uint8" },
          { name: "confidenceBps", type: "uint16" },
          { name: "modelId", type: "bytes32" },
          { name: "reasonsHash", type: "bytes32" },
          { name: "evidenceHash", type: "bytes32" },
          { name: "timestamp", type: "uint64" },
          { name: "nonce", type: "uint64" },
        ],
        name: "payload",
        type: "tuple",
      },
    ],
    name: "getPayloadDigestV2ByKey",
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

const riskEngineV2Abi = [
  {
    inputs: [{ name: "subject", type: "address" }],
    name: "evaluate",
    outputs: [
      {
        components: [
          { name: "score", type: "uint16" },
          { name: "tier", type: "uint8" },
          { name: "confidenceBps", type: "uint16" },
          { name: "modelId", type: "bytes32" },
          { name: "reasonCodes", type: "bytes32[]" },
          { name: "evidence", type: "bytes32[]" },
        ],
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "subjectId", type: "bytes32" }],
    name: "evaluateSubject",
    outputs: [
      {
        components: [
          { name: "score", type: "uint16" },
          { name: "tier", type: "uint8" },
          { name: "confidenceBps", type: "uint16" },
          { name: "modelId", type: "bytes32" },
          { name: "reasonCodes", type: "bytes32[]" },
          { name: "evidence", type: "bytes32[]" },
        ],
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;

const priceOracleAbi = [
  {
    inputs: [{ name: "asset", type: "address" }],
    name: "nextNonce",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        components: [
          { name: "asset", type: "address" },
          { name: "price", type: "uint256" },
          { name: "timestamp", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
        name: "payload",
        type: "tuple",
      },
    ],
    name: "getPricePayloadDigest",
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

const transport = http(RPC_URL);
const publicClient = createPublicClient({
  chain: { ...baseSepolia, id: CHAIN_ID },
  transport,
});

async function getRiskNonce(user: Hex): Promise<bigint> {
  return publicClient.readContract({
    address: RISK_ORACLE,
    abi: riskOracleAbi,
    functionName: "nextNonce",
    args: [user],
  }) as Promise<bigint>;
}

async function getPriceNonce(asset: Hex): Promise<bigint> {
  return publicClient.readContract({
    address: PRICE_ORACLE,
    abi: priceOracleAbi,
    functionName: "nextNonce",
    args: [asset],
  }) as Promise<bigint>;
}

const attestationRegistryAbi = [
  {
    inputs: [{ name: "subject", type: "address" }],
    name: "nextNonce",
    outputs: [{ name: "", type: "uint64" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "subjectId", type: "bytes32" }],
    name: "nextSubjectNonce",
    outputs: [{ name: "", type: "uint64" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

async function getAttestationNonce(subject: Hex): Promise<bigint> {
  return publicClient.readContract({
    address: ATTESTATION_REGISTRY,
    abi: attestationRegistryAbi,
    functionName: "nextNonce",
    args: [subject],
  }) as Promise<bigint>;
}

async function getSubjectAttestationNonce(subjectId: Hex): Promise<bigint> {
  return publicClient.readContract({
    address: ATTESTATION_REGISTRY,
    abi: attestationRegistryAbi,
    functionName: "nextSubjectNonce",
    args: [subjectId],
  }) as Promise<bigint>;
}

function isValidAddress(s: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(s);
}

function isValidBytes32(s: string): boolean {
  return /^0x[a-fA-F0-9]{64}$/.test(s);
}

// Naive in-memory rate limit: IP -> { count, resetAt }
const rateMap = new Map<string, { count: number; resetAt: number }>();
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 30;

function rateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateMap.get(ip);
  if (!entry) {
    rateMap.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (now > entry.resetAt) {
    rateMap.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  entry.count++;
  return entry.count <= RATE_MAX;
}

async function bootstrap() {
  const fastify = Fastify({ logger: true });

  await fastify.register(cors, {
    origin: process.env.CORS_ORIGIN ?? true,
    methods: ["GET", "POST"],
  });

  fastify.addHook("preHandler", (req, _reply, done) => {
    const ip = req.ip ?? req.headers["x-forwarded-for"] ?? "unknown";
    if (!rateLimit(ip)) {
      return done(new Error("Rate limit exceeded") as any);
    }
    done();
  });

  fastify.get("/health", async () => {
    const hasConfig =
      RISK_ORACLE &&
      PRICE_ORACLE &&
      RISK_KEY &&
      PRICE_KEY;
    return {
      ok: true,
      chainId: CHAIN_ID,
      configured: !!hasConfig,
    };
  });

  fastify.post<{
    Body: { user: string };
  }>("/risk/evaluate-and-sign", async (req, reply) => {
    if (!RISK_KEY || !RISK_ORACLE || !RISK_ENGINE_V2) {
      return reply.status(503).send({ error: "Risk v2 signer not configured" });
    }

    const { user } = req.body ?? {};
    if (!user || !isValidAddress(user)) {
      return reply.status(400).send({ error: "Missing or invalid body: { user }" });
    }
    const liveChainId = await publicClient.getChainId();
    if (liveChainId !== CHAIN_ID) {
      return reply.status(500).send({
        error: `Chain ID mismatch: configured=${CHAIN_ID}, live=${liveChainId}`,
      });
    }

    let evaluation: {
      score: number;
      tier: number;
      confidenceBps: number;
      modelId: Hex;
      reasonCodes: readonly Hex[];
      evidence: readonly Hex[];
    };
    try {
      evaluation = (await publicClient.readContract({
        address: RISK_ENGINE_V2,
        abi: riskEngineV2Abi,
        functionName: "evaluate",
        args: [user as Hex],
      })) as typeof evaluation;
    } catch {
      return reply.status(500).send({ error: "RiskEngine evaluate failed" });
    }

    const reasonsHash = keccak256(
      encodeAbiParameters([{ type: "bytes32[]" }], [evaluation.reasonCodes as Hex[]])
    );
    const evidenceHash = keccak256(
      encodeAbiParameters([{ type: "bytes32[]" }], [evaluation.evidence as Hex[]])
    );

    if (EXPECTED_RISK_MODEL_ID && EXPECTED_RISK_MODEL_ID !== evaluation.modelId) {
      fastify.log.warn({
        msg: "Risk model mismatch",
        expected: EXPECTED_RISK_MODEL_ID,
        got: evaluation.modelId,
      });
    }

    let nonce: bigint;
    try {
      nonce = await getRiskNonce(user as Hex);
    } catch {
      return reply.status(500).send({ error: "Risk nonce fetch failed" });
    }

    const timestamp = BigInt(Math.floor(Date.now() / 1000));
    const payload = {
      user: user as Hex,
      score: evaluation.score,
      riskTier: evaluation.tier,
      confidenceBps: evaluation.confidenceBps,
      modelId: evaluation.modelId,
      reasonsHash,
      evidenceHash,
      timestamp,
      nonce,
    };

    const domain = {
      name: "OCX Risk Oracle",
      version: "1",
      chainId: CHAIN_ID,
      verifyingContract: RISK_ORACLE,
    };

    const types = {
      RiskPayloadV2: [
        { name: "user", type: "address" },
        { name: "score", type: "uint16" },
        { name: "riskTier", type: "uint8" },
        { name: "confidenceBps", type: "uint16" },
        { name: "modelId", type: "bytes32" },
        { name: "reasonsHash", type: "bytes32" },
        { name: "evidenceHash", type: "bytes32" },
        { name: "timestamp", type: "uint64" },
        { name: "nonce", type: "uint64" },
      ],
    } as const;

    const account = privateKeyToAccount(RISK_KEY as Hex);
    const wallet = createWalletClient({
      account,
      chain: { ...baseSepolia, id: CHAIN_ID },
      transport,
    });

    let signature: Hash;
    try {
      signature = await wallet.signTypedData({
        domain,
        types,
        primaryType: "RiskPayloadV2",
        message: payload,
      });
    } catch (e) {
      fastify.log.error(e);
      return reply.status(500).send({ error: "Risk v2 signing failed" });
    }

    return {
      payload: {
        user: payload.user,
        score: payload.score.toString(),
        riskTier: payload.riskTier.toString(),
        confidenceBps: payload.confidenceBps.toString(),
        modelId: payload.modelId,
        reasonsHash: payload.reasonsHash,
        evidenceHash: payload.evidenceHash,
        timestamp: payload.timestamp.toString(),
        nonce: payload.nonce.toString(),
      },
      signature,
      debug: {
        reasonCodes: evaluation.reasonCodes,
        evidence: evaluation.evidence,
      },
    };
  });

  fastify.post<{
    Body: { subjectId: string };
  }>("/risk/evaluate-subject-and-sign", async (req, reply) => {
    if (!RISK_KEY || !RISK_ORACLE || !RISK_ENGINE_V2) {
      return reply.status(503).send({ error: "Risk v2 signer not configured" });
    }

    const { subjectId } = req.body ?? {};
    if (!subjectId || !isValidBytes32(subjectId)) {
      return reply.status(400).send({ error: "Missing or invalid body: { subjectId } (bytes32)" });
    }

    const liveChainId = await publicClient.getChainId();
    if (liveChainId !== CHAIN_ID) {
      return reply.status(500).send({
        error: `Chain ID mismatch: configured=${CHAIN_ID}, live=${liveChainId}`,
      });
    }

    let evaluation: {
      score: number;
      tier: number;
      confidenceBps: number;
      modelId: Hex;
      reasonCodes: readonly Hex[];
      evidence: readonly Hex[];
    };
    try {
      evaluation = (await publicClient.readContract({
        address: RISK_ENGINE_V2,
        abi: riskEngineV2Abi,
        functionName: "evaluateSubject",
        args: [subjectId as Hex],
      })) as typeof evaluation;
    } catch {
      return reply.status(500).send({ error: "RiskEngine evaluateSubject failed" });
    }

    const reasonsHash = keccak256(
      encodeAbiParameters([{ type: "bytes32[]" }], [evaluation.reasonCodes as Hex[]])
    );
    const evidenceHash = keccak256(
      encodeAbiParameters([{ type: "bytes32[]" }], [evaluation.evidence as Hex[]])
    );

    if (EXPECTED_RISK_MODEL_ID && EXPECTED_RISK_MODEL_ID !== evaluation.modelId) {
      fastify.log.warn({
        msg: "Risk model mismatch (subject)",
        expected: EXPECTED_RISK_MODEL_ID,
        got: evaluation.modelId,
      });
    }

    let nonce: bigint;
    try {
      nonce = await publicClient.readContract({
        address: RISK_ORACLE,
        abi: riskOracleAbi,
        functionName: "nextNonceKey",
        args: [subjectId as Hex],
      }) as bigint;
    } catch {
      return reply.status(500).send({ error: "Risk nonce key fetch failed" });
    }

    const timestamp = BigInt(Math.floor(Date.now() / 1000));
    const payload = {
      subjectKey: subjectId as Hex,
      score: evaluation.score,
      riskTier: evaluation.tier,
      confidenceBps: evaluation.confidenceBps,
      modelId: evaluation.modelId,
      reasonsHash,
      evidenceHash,
      timestamp,
      nonce,
    };

    const domain = {
      name: "OCX Risk Oracle",
      version: "1",
      chainId: CHAIN_ID,
      verifyingContract: RISK_ORACLE,
    };

    const types = {
      RiskPayloadV2ByKey: [
        { name: "subjectKey", type: "bytes32" },
        { name: "score", type: "uint16" },
        { name: "riskTier", type: "uint8" },
        { name: "confidenceBps", type: "uint16" },
        { name: "modelId", type: "bytes32" },
        { name: "reasonsHash", type: "bytes32" },
        { name: "evidenceHash", type: "bytes32" },
        { name: "timestamp", type: "uint64" },
        { name: "nonce", type: "uint64" },
      ],
    } as const;

    const account = privateKeyToAccount(RISK_KEY as Hex);
    const wallet = createWalletClient({
      account,
      chain: { ...baseSepolia, id: CHAIN_ID },
      transport,
    });

    let signature: Hash;
    try {
      signature = await wallet.signTypedData({
        domain,
        types,
        primaryType: "RiskPayloadV2ByKey",
        message: payload,
      });
    } catch (e) {
      fastify.log.error(e);
      return reply.status(500).send({ error: "Risk v2 by-key signing failed" });
    }

    return {
      payload: {
        subjectKey: payload.subjectKey,
        score: payload.score.toString(),
        riskTier: payload.riskTier.toString(),
        confidenceBps: payload.confidenceBps.toString(),
        modelId: payload.modelId,
        reasonsHash: payload.reasonsHash,
        evidenceHash: payload.evidenceHash,
        timestamp: payload.timestamp.toString(),
        nonce: payload.nonce.toString(),
      },
      signature,
      debug: {
        reasonCodes: evaluation.reasonCodes,
        evidence: evaluation.evidence,
      },
    };
  });

  fastify.post<{
    Body: { user: string; score: number; riskTier: number };
  }>("/risk/sign", async (req, reply) => {
    if (!RISK_KEY || !RISK_ORACLE) {
      return reply.status(503).send({ error: "Risk signer not configured" });
    }

    const { user, score, riskTier } = req.body ?? {};
    if (!user || typeof score !== "number" || typeof riskTier !== "number") {
      return reply.status(400).send({
        error: "Missing or invalid body: { user, score, riskTier }",
      });
    }

    if (!isValidAddress(user)) {
      return reply.status(400).send({ error: "Invalid user address" });
    }
    if (score < 0 || score > 1000) {
      return reply.status(400).send({ error: "Score must be 0-1000" });
    }
    if (riskTier < 0 || riskTier > 5) {
      return reply.status(400).send({ error: "Risk tier must be 0-5" });
    }

    const timestamp = BigInt(Math.floor(Date.now() / 1000));
    let nonce: bigint;
    try {
      nonce = await getRiskNonce(user as Hex);
    } catch (e) {
      return reply.status(500).send({ error: "Nonce fetch failed" });
    }

    const payload = {
      user: user as Hex,
      score: BigInt(score),
      riskTier: BigInt(riskTier),
      timestamp,
      nonce,
    };

    const domain = {
      name: "OCX Risk Oracle",
      version: "1",
      chainId: CHAIN_ID,
      verifyingContract: RISK_ORACLE,
    };

    const types = {
      RiskPayload: [
        { name: "user", type: "address" },
        { name: "score", type: "uint256" },
        { name: "riskTier", type: "uint256" },
        { name: "timestamp", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    } as const;

    const account = privateKeyToAccount(RISK_KEY as Hex);
    const wallet = createWalletClient({
      account,
      chain: { ...baseSepolia, id: CHAIN_ID },
      transport,
    });

    let signature: Hash;
    try {
      signature = await wallet.signTypedData({
        domain,
        types,
        primaryType: "RiskPayload",
        message: payload,
      });
    } catch (e) {
      fastify.log.error(e);
      return reply.status(500).send({ error: "Signing failed" });
    }

    // Optional digest sanity check: verify onchain digest matches our typed data
    if (process.env.VERIFY_DIGEST === "true") {
      try {
        const onchainDigest = await publicClient.readContract({
          address: RISK_ORACLE,
          abi: riskOracleAbi,
          functionName: "getPayloadDigest",
          args: [payload],
        });
        const ok = await publicClient.verifyTypedData({
          address: account.address,
          domain,
          types,
          primaryType: "RiskPayload",
          message: payload,
          signature,
        });
        if (!ok) {
          fastify.log.warn("verifyTypedData failed");
          return reply.status(500).send({ error: "Digest consistency check failed" });
        }
      } catch (e) {
        fastify.log.warn({ msg: "Digest check error", error: String(e) });
      }
    }

    return {
      payload: {
        user: payload.user,
        score: payload.score.toString(),
        riskTier: payload.riskTier.toString(),
        timestamp: payload.timestamp.toString(),
        nonce: payload.nonce.toString(),
      },
      signature,
    };
  });

  fastify.post<{
    Body: { asset: string; priceUSD8: string };
  }>("/price/sign", async (req, reply) => {
    if (!PRICE_KEY || !PRICE_ORACLE) {
      return reply.status(503).send({ error: "Price signer not configured" });
    }

    const { asset, priceUSD8 } = req.body ?? {};
    if (!asset || !priceUSD8) {
      return reply.status(400).send({
        error: "Missing body: { asset, priceUSD8 }",
      });
    }

    if (!isValidAddress(asset)) {
      return reply.status(400).send({ error: "Invalid asset address" });
    }

    const priceUSD8Big = BigInt(priceUSD8);
    if (priceUSD8Big <= 0n) {
      return reply.status(400).send({ error: "Price must be > 0" });
    }

    const timestamp = BigInt(Math.floor(Date.now() / 1000));
    let nonce: bigint;
    try {
      nonce = await getPriceNonce(asset as Hex);
    } catch (e) {
      return reply.status(500).send({ error: "Nonce fetch failed" });
    }

    const payload = {
      asset: asset as Hex,
      price: priceUSD8Big,
      timestamp,
      nonce,
    };

    const domain = {
      name: "OCX Price Oracle",
      version: "1",
      chainId: CHAIN_ID,
      verifyingContract: PRICE_ORACLE,
    };

    const types = {
      PricePayload: [
        { name: "asset", type: "address" },
        { name: "price", type: "uint256" },
        { name: "timestamp", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    } as const;

    const account = privateKeyToAccount(PRICE_KEY as Hex);
    const wallet = createWalletClient({
      account,
      chain: { ...baseSepolia, id: CHAIN_ID },
      transport,
    });

    let signature: Hash;
    try {
      signature = await wallet.signTypedData({
        domain,
        types,
        primaryType: "PricePayload",
        message: payload,
      });
    } catch (e) {
      fastify.log.error(e);
      return reply.status(500).send({ error: "Signing failed" });
    }

    return {
      payload: {
        asset: payload.asset,
        price: payload.price.toString(),
        priceUSD8: payload.price.toString(),
        timestamp: payload.timestamp.toString(),
        nonce: payload.nonce.toString(),
      },
      signature,
    };
  });

  fastify.post<{
    Body: {
      subject: string;
      attestationType: string;
      dataHash: string;
      data?: string;
      uri?: string;
      expiresAt?: string;
    };
  }>("/attestation/sign", async (req, reply) => {
    if (!ATTESTATION_KEY || !ATTESTATION_REGISTRY) {
      return reply.status(503).send({ error: "Attestation signer not configured" });
    }

    const { subject, attestationType, dataHash, data = "0x0000000000000000000000000000000000000000000000000000000000000000", uri = "", expiresAt = "0" } = req.body ?? {};
    if (!subject || !attestationType || !dataHash) {
      return reply.status(400).send({
        error: "Missing body: { subject, attestationType, dataHash }",
      });
    }

    if (!isValidAddress(subject)) {
      return reply.status(400).send({ error: "Invalid subject address" });
    }

    const attestationTypeBytes: Hex =
      attestationType.startsWith("0x") && attestationType.length === 66
        ? (attestationType as Hex)
        : (keccak256(new TextEncoder().encode(attestationType)) as Hex);

    const dataHashBytes = dataHash.startsWith("0x") ? (dataHash as Hex) : (`0x${dataHash}` as Hex);
    if (dataHashBytes.length !== 66) {
      return reply.status(400).send({ error: "dataHash must be 32 bytes (0x + 64 hex)" });
    }

    let dataBytes: Hex;
    if (typeof data === "string" && data.startsWith("0x") && data.length === 66) {
      dataBytes = data as Hex;
    } else if (data === "" || data === "0") {
      dataBytes = "0x0000000000000000000000000000000000000000000000000000000000000000" as Hex;
    } else {
      const n = BigInt(data as string);
      dataBytes = (`0x${n.toString(16).padStart(64, "0")}` as Hex);
    }

    const issuedAt = BigInt(Math.floor(Date.now() / 1000));
    const expiresAtBig = BigInt(expiresAt);
    if (expiresAtBig !== 0n && expiresAtBig <= issuedAt) {
      return reply.status(400).send({ error: "expiresAt must be 0 or > issuedAt" });
    }

    let nonce: bigint;
    try {
      nonce = await getAttestationNonce(subject as Hex);
    } catch (e) {
      return reply.status(500).send({ error: "Attestation nonce fetch failed" });
    }

    const payload = {
      subject: subject as Hex,
      attestationType: attestationTypeBytes as `0x${string}`,
      dataHash: dataHashBytes as `0x${string}`,
      data: dataBytes as `0x${string}`,
      uri: uri || "",
      issuedAt,
      expiresAt: expiresAtBig,
      nonce,
    };

    const domain = {
      name: "OCX Attestation Registry",
      version: "2",
      chainId: CHAIN_ID,
      verifyingContract: ATTESTATION_REGISTRY,
    };

    const types = {
      Attestation: [
        { name: "subject", type: "address" },
        { name: "attestationType", type: "bytes32" },
        { name: "dataHash", type: "bytes32" },
        { name: "data", type: "bytes32" },
        { name: "uri", type: "string" },
        { name: "issuedAt", type: "uint64" },
        { name: "expiresAt", type: "uint64" },
        { name: "nonce", type: "uint64" },
      ],
    } as const;

    const account = privateKeyToAccount(ATTESTATION_KEY as Hex);
    const wallet = createWalletClient({
      account,
      chain: { ...baseSepolia, id: CHAIN_ID },
      transport,
    });

    let signature: Hash;
    try {
      signature = await wallet.signTypedData({
        domain,
        types,
        primaryType: "Attestation",
        message: payload,
      });
    } catch (e) {
      fastify.log.error(e);
      return reply.status(500).send({ error: "Attestation signing failed" });
    }

    return {
      payload: {
        subject: payload.subject,
        attestationType: payload.attestationType,
        dataHash: payload.dataHash,
        data: payload.data,
        uri: payload.uri,
        issuedAt: payload.issuedAt.toString(),
        expiresAt: payload.expiresAt.toString(),
        nonce: payload.nonce.toString(),
      },
      signature,
    };
  });

  fastify.post<{
    Body: {
      subjectId: string;
      attestationType: string;
      dataHash: string;
      data?: string;
      uri?: string;
      expiresAt?: string;
    };
  }>("/attestation/subject-sign", async (req, reply) => {
    if (!ATTESTATION_KEY || !ATTESTATION_REGISTRY) {
      return reply.status(503).send({ error: "Attestation signer not configured" });
    }

    const {
      subjectId,
      attestationType,
      dataHash,
      data = "0x0000000000000000000000000000000000000000000000000000000000000000",
      uri = "",
      expiresAt = "0",
    } = req.body ?? {};
    if (!subjectId || !attestationType || !dataHash) {
      return reply.status(400).send({
        error: "Missing body: { subjectId, attestationType, dataHash }",
      });
    }
    if (!isValidBytes32(subjectId)) {
      return reply.status(400).send({ error: "Invalid subjectId bytes32" });
    }

    const attestationTypeBytes: Hex =
      attestationType.startsWith("0x") && attestationType.length === 66
        ? (attestationType as Hex)
        : (keccak256(new TextEncoder().encode(attestationType)) as Hex);

    const dataHashBytes = dataHash.startsWith("0x") ? (dataHash as Hex) : (`0x${dataHash}` as Hex);
    if (dataHashBytes.length !== 66) {
      return reply.status(400).send({ error: "dataHash must be 32 bytes (0x + 64 hex)" });
    }

    let dataBytes: Hex;
    if (typeof data === "string" && data.startsWith("0x") && data.length === 66) {
      dataBytes = data as Hex;
    } else if (data === "" || data === "0") {
      dataBytes = "0x0000000000000000000000000000000000000000000000000000000000000000" as Hex;
    } else {
      const n = BigInt(data as string);
      dataBytes = (`0x${n.toString(16).padStart(64, "0")}` as Hex);
    }

    const issuedAt = BigInt(Math.floor(Date.now() / 1000));
    const expiresAtBig = BigInt(expiresAt);
    if (expiresAtBig !== 0n && expiresAtBig <= issuedAt) {
      return reply.status(400).send({ error: "expiresAt must be 0 or > issuedAt" });
    }

    let nonce: bigint;
    try {
      nonce = await getSubjectAttestationNonce(subjectId as Hex);
    } catch {
      return reply.status(500).send({ error: "Subject attestation nonce fetch failed" });
    }

    const payload = {
      subjectId: subjectId as Hex,
      attestationType: attestationTypeBytes as `0x${string}`,
      dataHash: dataHashBytes as `0x${string}`,
      data: dataBytes as `0x${string}`,
      uri: uri || "",
      issuedAt,
      expiresAt: expiresAtBig,
      nonce,
    };

    const domain = {
      name: "OCX Attestation Registry",
      version: "2",
      chainId: CHAIN_ID,
      verifyingContract: ATTESTATION_REGISTRY,
    };

    const types = {
      SubjectAttestation: [
        { name: "subjectId", type: "bytes32" },
        { name: "attestationType", type: "bytes32" },
        { name: "dataHash", type: "bytes32" },
        { name: "data", type: "bytes32" },
        { name: "uri", type: "string" },
        { name: "issuedAt", type: "uint64" },
        { name: "expiresAt", type: "uint64" },
        { name: "nonce", type: "uint64" },
      ],
    } as const;

    const account = privateKeyToAccount(ATTESTATION_KEY as Hex);
    const wallet = createWalletClient({
      account,
      chain: { ...baseSepolia, id: CHAIN_ID },
      transport,
    });

    let signature: Hash;
    try {
      signature = await wallet.signTypedData({
        domain,
        types,
        primaryType: "SubjectAttestation",
        message: payload,
      });
    } catch (e) {
      fastify.log.error(e);
      return reply.status(500).send({ error: "Subject attestation signing failed" });
    }

    return {
      payload: {
        subjectId: payload.subjectId,
        attestationType: payload.attestationType,
        dataHash: payload.dataHash,
        data: payload.data,
        uri: payload.uri,
        issuedAt: payload.issuedAt.toString(),
        expiresAt: payload.expiresAt.toString(),
        nonce: payload.nonce.toString(),
      },
      signature,
    };
  });

  fastify.setErrorHandler((err: any, req, reply) => {
    if (err.message === "Rate limit exceeded") {
      return reply.status(429).send({ error: "Rate limit exceeded" });
    }
    fastify.log.error(err);
    reply.status(500).send({ error: "Internal server error" });
  });

  await fastify.listen({ port: PORT, host: "0.0.0.0" });
  console.log(`Oracle signer listening on http://0.0.0.0:${PORT}`);
}

bootstrap().catch((e) => {
  console.error(e);
  process.exit(1);
});
