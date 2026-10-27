import {
  constructFactoryPositionOperation,
  type FactoryPositionLedger,
} from "../vendor/client/src/factory/position-operation.ts";
export interface FactoryMintLedger extends FactoryPositionLedger {
  /** Exact SHARE base units to issue into an existing position. */
  shares: bigint;
  /** Maximum principal base units the user permits as input. */
  maxAssets: bigint;
  maxRewardInput: bigint;
}

/** Exact-share CTVS mint uses Stake underneath, including bounded reward equalization. */
export function constructFactoryMint(input: FactoryMintLedger) {
  return constructFactoryPositionOperation({
    ...input,
    operation: "mint",
    amount: input.shares,
    bound: input.maxAssets,
  });
}
