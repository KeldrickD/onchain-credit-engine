/**
 * Snapshot and incident types
 */

export interface MonitorConfig {
  chainId: number;
  network: string;
  contracts: {
    loanEngine: string;
    vault: string;
    priceOracle: string;
    registry: string;
    liqManager: string;
  };
}

export interface PriceUpdateEvent {
  blockNumber: number;
  txHash: string;
  asset: string;
  price: string;
  timestamp?: number;
}

export interface LiquidationEvent {
  blockNumber: number;
  txHash: string;
  borrower: string;
  liquidator: string;
  repayAmount: string;
  collateralSeized: string;
}

export interface LoanEvent {
  blockNumber: number;
  txHash: string;
  borrower: string;
  principalAmount?: string;
  collateralAmount?: string;
  ltvBps?: number;
  rateBps?: number;
  amount?: string;
  remainingPrincipal?: string;
  type: "LoanOpened" | "LoanRepaid" | "CollateralDeposited" | "CollateralWithdrawn" | "LiquidationRepay" | "CollateralSeized";
}

export interface SnapshotMeta {
  chainId: number;
  network: string;
  fromBlock: number;
  toBlock: number;
  generatedAt: string;
}

export interface Snapshot {
  meta: SnapshotMeta;
  contracts: Record<string, string>;
  counts: {
    loanOpened: number;
    liquidations: number;
    priceUpdates: number;
    repays: number;
    creditProfileUpdates: number;
    deposits: number;
    withdrawals: number;
  };
  lastSeen: {
    priceUpdateBlock: number;
    priceUpdateAt: string;
    loanOpenedBlock: number;
  };
  events: {
    priceUpdates: PriceUpdateEvent[];
    liquidations: LiquidationEvent[];
    loans: LoanEvent[];
  };
  anomalies: string[];
  riskContext?: RiskContext;
}

export interface RiskContext {
  latestSim: {
    path: string;
    summary: {
      liqFreq: number;
      expectedLossPct: number;
      mostSensitiveInputs: string[];
    };
  };
}

export interface IncidentExport {
  id: string;
  triggeredRules: string[];
  timeWindow: {
    fromBlock: number;
    toBlock: number;
    fromTimestamp?: number;
    toTimestamp?: number;
  };
  topTxs: string[];
  decodedEvents: unknown[];
  configSnapshot: Record<string, unknown>;
  riskSimSummary?: RiskContext["latestSim"]["summary"];
  recommendedActions: string[];
  notes: string;
}
