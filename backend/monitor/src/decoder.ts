/**
 * Event decoder - maps raw logs to typed events
 */

import { decodeEventLog } from "viem";
import {
  PRICE_UPDATED_ABI,
  CREDIT_PROFILE_UPDATED_ABI,
  LOAN_ENGINE_ABI,
  LIQUIDATED_ABI,
  VAULT_ABI,
} from "./abis.js";
import type { PriceUpdateEvent, LiquidationEvent, LoanEvent } from "./types.js";

interface RawLog {
  blockNumber: bigint;
  transactionHash: string;
  address: string;
  topics: readonly string[];
  data: `0x${string}`;
}

export function decodeLog(log: RawLog): PriceUpdateEvent | LiquidationEvent | LoanEvent | null {
  try {
    const decoded = decodeEventLog({
      abi: [
        ...PRICE_UPDATED_ABI,
        ...CREDIT_PROFILE_UPDATED_ABI,
        ...LOAN_ENGINE_ABI,
        ...LIQUIDATED_ABI,
        ...VAULT_ABI,
      ],
      data: log.data,
      topics: log.topics as [`0x${string}`, ...`0x${string}`[]],
    });

    const blockNumber = Number(log.blockNumber);
    const txHash = log.transactionHash;

    switch (decoded.eventName) {
      case "PriceUpdated": {
        return {
          blockNumber,
          txHash,
          asset: (decoded.args as { asset: string }).asset,
          price: String((decoded.args as { price: bigint }).price),
        };
      }
      case "CreditProfileUpdated":
        return null; // not in our output shape, skip

      case "CollateralDeposited": {
        const a = decoded.args as { user: string; amount: bigint };
        return {
          blockNumber,
          txHash,
          borrower: a.user,
          amount: String(a.amount),
          type: "CollateralDeposited",
        };
      }
      case "LoanOpened": {
        const a = decoded.args as {
          borrower: string;
          collateralAmount: bigint;
          principalAmount: bigint;
          ltvBps: bigint;
          interestRateBps: bigint;
        };
        return {
          blockNumber,
          txHash,
          borrower: a.borrower,
          collateralAmount: String(a.collateralAmount),
          principalAmount: String(a.principalAmount),
          ltvBps: Number(a.ltvBps),
          rateBps: Number(a.interestRateBps),
          type: "LoanOpened",
        };
      }
      case "LoanRepaid": {
        const a = decoded.args as { borrower: string; amount: bigint; remainingPrincipal: bigint };
        return {
          blockNumber,
          txHash,
          borrower: a.borrower,
          amount: String(a.amount),
          remainingPrincipal: String(a.remainingPrincipal),
          type: "LoanRepaid",
        };
      }
      case "CollateralWithdrawn": {
        const a = decoded.args as { user: string; amount: bigint };
        return {
          blockNumber,
          txHash,
          borrower: a.user,
          amount: String(a.amount),
          type: "CollateralWithdrawn",
        };
      }
      case "LiquidationRepay": {
        const a = decoded.args as { borrower: string; amount: bigint; remainingPrincipal: bigint };
        return {
          blockNumber,
          txHash,
          borrower: a.borrower,
          amount: String(a.amount),
          remainingPrincipal: String(a.remainingPrincipal),
          type: "LiquidationRepay",
        };
      }
      case "CollateralSeized": {
        const a = decoded.args as { borrower: string; to: string; amount: bigint };
        return {
          blockNumber,
          txHash,
          borrower: a.borrower,
          amount: String(a.amount),
          type: "CollateralSeized",
        };
      }
      case "Liquidated": {
        const a = decoded.args as {
          borrower: string;
          liquidator: string;
          repayAmount: bigint;
          collateralSeized: bigint;
        };
        return {
          blockNumber,
          txHash,
          borrower: a.borrower,
          liquidator: a.liquidator,
          repayAmount: String(a.repayAmount),
          collateralSeized: String(a.collateralSeized),
        };
      }
      case "Deposited":
      case "Withdrawn":
        return null; // vault events - counted but not in loan/price/liquidation arrays

      default:
        return null;
    }
  } catch {
    return null;
  }
}

