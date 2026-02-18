export const CHAINS = {
  baseSepolia: 84532,
} as const;

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

export const contractAddresses = {
  creditRegistry: (process.env.NEXT_PUBLIC_CREDIT_REGISTRY_ADDRESS || ZERO) as `0x${string}`,
  loanEngine: (process.env.NEXT_PUBLIC_LOAN_ENGINE_ADDRESS || ZERO) as `0x${string}`,
  priceRouter: (process.env.NEXT_PUBLIC_PRICE_ROUTER_ADDRESS || ZERO) as `0x${string}`,
  collateralManager: (process.env.NEXT_PUBLIC_COLLATERAL_MANAGER_ADDRESS || ZERO) as `0x${string}`,
  treasuryVault: (process.env.NEXT_PUBLIC_TREASURY_VAULT_ADDRESS || ZERO) as `0x${string}`,
  signedPriceOracle: (process.env.NEXT_PUBLIC_SIGNED_PRICE_ORACLE_ADDRESS || ZERO) as `0x${string}`,
  attestationRegistry: (process.env.NEXT_PUBLIC_ATTESTATION_REGISTRY_ADDRESS || ZERO) as `0x${string}`,
  riskEngineV2: (process.env.NEXT_PUBLIC_RISK_ENGINE_V2_ADDRESS || ZERO) as `0x${string}`,
  dealFactory: (process.env.NEXT_PUBLIC_DEAL_FACTORY_ADDRESS || ZERO) as `0x${string}`,
  subjectRegistry: (process.env.NEXT_PUBLIC_SUBJECT_REGISTRY_ADDRESS || ZERO) as `0x${string}`,
  usdc: (process.env.NEXT_PUBLIC_USDC_ADDRESS || ZERO) as `0x${string}`,
  weth: (process.env.NEXT_PUBLIC_WETH_ADDRESS || ZERO) as `0x${string}`,
  wbtc: (process.env.NEXT_PUBLIC_WBTC_ADDRESS || ZERO) as `0x${string}`,
};

export const adminAddress = (process.env.NEXT_PUBLIC_ADMIN_ADDRESS || "") as string;

export const oracleSignerUrl = process.env.NEXT_PUBLIC_ORACLE_SIGNER_URL || "http://localhost:3001";
