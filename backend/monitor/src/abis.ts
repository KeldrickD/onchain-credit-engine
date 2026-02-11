/**
 * Event ABIs for decoding (from contracts/out)
 */

export const PRICE_UPDATED_ABI = [
  {
    type: "event",
    name: "PriceUpdated",
    inputs: [
      { name: "asset", type: "address", indexed: true },
      { name: "price", type: "uint256", indexed: false },
    ],
  },
] as const;

export const CREDIT_PROFILE_UPDATED_ABI = [
  {
    type: "event",
    name: "CreditProfileUpdated",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "score", type: "uint256", indexed: false },
      { name: "riskTier", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
      { name: "nonce", type: "uint256", indexed: false },
    ],
  },
] as const;

export const LOAN_ENGINE_ABI = [
  {
    type: "event",
    name: "CollateralDeposited",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "LoanOpened",
    inputs: [
      { name: "borrower", type: "address", indexed: true },
      { name: "collateralAmount", type: "uint256", indexed: false },
      { name: "principalAmount", type: "uint256", indexed: false },
      { name: "ltvBps", type: "uint256", indexed: false },
      { name: "interestRateBps", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "LoanRepaid",
    inputs: [
      { name: "borrower", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "remainingPrincipal", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CollateralWithdrawn",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "LiquidationRepay",
    inputs: [
      { name: "borrower", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "remainingPrincipal", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CollateralSeized",
    inputs: [
      { name: "borrower", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

export const LIQUIDATED_ABI = [
  {
    type: "event",
    name: "Liquidated",
    inputs: [
      { name: "borrower", type: "address", indexed: true },
      { name: "liquidator", type: "address", indexed: true },
      { name: "repayAmount", type: "uint256", indexed: false },
      { name: "collateralSeized", type: "uint256", indexed: false },
    ],
  },
] as const;

export const VAULT_ABI = [
  {
    type: "event",
    name: "Deposited",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Withdrawn",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;
