import {
	constructFactoryPositionOperation,
	type FactoryPositionLedger,
} from "./position-operation.ts";
export interface FactoryWithdrawLedger extends FactoryPositionLedger {
	/** Exact net principal base units requested by the receiver. */
	assets: bigint;
	/** Maximum SHARE base units permitted to burn. */
	maxShares: bigint;
}
/** Asset-specified CTVS withdraw with atomic WithdrawAndClaim underneath. */
export function constructFactoryWithdraw(input: FactoryWithdrawLedger) {
	return constructFactoryPositionOperation({
		...input,
		operation: "withdraw",
		amount: input.assets,
		bound: input.maxShares,
	});
}
