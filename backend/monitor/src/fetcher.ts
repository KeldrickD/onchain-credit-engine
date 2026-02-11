/**
 * Chunked log fetcher to avoid RPC limits
 */

import { createPublicClient, http } from "viem";
import type { Address } from "viem";

export interface FetchLogsOptions {
  rpcUrl: string;
  fromBlock: bigint;
  toBlock: bigint;
  step: bigint;
  addresses: {
    priceOracle?: Address;
    registry?: Address;
    loanEngine?: Address;
    liqManager?: Address;
    vault?: Address;
  };
}

export interface RawLog {
  blockNumber: bigint;
  transactionHash: string;
  address: Address;
  topics: readonly [`0x${string}`];
  data: `0x${string}`;
}

export async function fetchLogsChunked(options: FetchLogsOptions): Promise<RawLog[]> {
  const client = createPublicClient({
    transport: http(options.rpcUrl),
  });

  const allLogs: RawLog[] = [];
  let from = options.fromBlock;
  const to = options.toBlock;

  while (from <= to) {
    const chunkTo = from + options.step - 1n > to ? to : from + options.step - 1n;

    const addrs = [
      options.addresses.priceOracle,
      options.addresses.registry,
      options.addresses.loanEngine,
      options.addresses.liqManager,
      options.addresses.vault,
    ].filter((a): a is Address => !!a && a.length === 42);
    if (addrs.length === 0) break;
    const logs = await client.getLogs({
      address: addrs,
      fromBlock: from,
      toBlock: chunkTo,
      strict: false,
    });

    for (const log of logs) {
      allLogs.push({
        blockNumber: log.blockNumber!,
        transactionHash: log.transactionHash!,
        address: log.address,
        topics: log.topics as readonly [`0x${string}`],
        data: log.data,
      });
    }

    from = chunkTo + 1n;
  }

  allLogs.sort((a, b) => {
    const blockDiff = Number(a.blockNumber - b.blockNumber);
    if (blockDiff !== 0) return blockDiff;
    return a.transactionHash.localeCompare(b.transactionHash);
  });

  return allLogs;
}
