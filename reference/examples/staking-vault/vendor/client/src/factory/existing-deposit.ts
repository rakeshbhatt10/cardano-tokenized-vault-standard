import {
	constructFactoryPositionOperation,
	type FactoryPositionLedger,
} from "./position-operation.ts";
export interface FactoryExistingDepositLedger extends FactoryPositionLedger {
	assets: bigint;
	minShares: bigint;
	maxRewardInput: bigint;
}
/** Deposit/top-up/re-entry reuses its existing position and never mints its NFT again. */
export function constructFactoryExistingDeposit(
	input: FactoryExistingDepositLedger,
) {
	return constructFactoryPositionOperation({
		...input,
		operation: "deposit",
		amount: input.assets,
		bound: input.minShares,
	});
}
