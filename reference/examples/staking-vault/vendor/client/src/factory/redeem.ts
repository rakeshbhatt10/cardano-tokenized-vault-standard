import {
	constructFactoryPositionOperation,
	type FactoryPositionLedger,
} from "./position-operation.ts";
export interface FactoryRedeemLedger extends FactoryPositionLedger {
	/** Exact SHARE base units to burn, never a principal token amount. */
	shares: bigint;
}
/** Share-specified atomic exit and claim; preserves the established redeem API. */
export function constructFactoryRedeem(input: FactoryRedeemLedger) {
	return constructFactoryPositionOperation({
		...input,
		operation: "redeem",
		amount: input.shares,
	});
}
