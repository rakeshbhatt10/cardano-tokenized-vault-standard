import { Constr, Data } from "@lucid-evolution/lucid";
import type { PoolRewards, PositionRewards } from "./rewards.ts";

export type PoolState = PoolRewards & {
	rewardDurationSeconds: bigint;
	isPaused: boolean;
	isLocked: boolean;
};
export function encodePoolDatum(pool: PoolState): string {
	return Data.to(
		new Constr(0, [
			new Constr(0, [
				pool.totalStaked,
				pool.rewardDurationSeconds,
				pool.periodFinishSeconds,
				pool.rewardRate,
				pool.lastUpdateSeconds,
				pool.rewardPerTokenStored,
				pool.accruedLiabilityBound,
				new Constr(pool.isPaused ? 1 : 0, []),
				new Constr(pool.isLocked ? 1 : 0, []),
			]),
		]),
	);
}
export function decodePoolDatum(cbor: string): PoolState {
	const outer = Data.from(cbor);
	if (
		!(outer instanceof Constr) ||
		outer.index !== 0 ||
		outer.fields.length !== 1
	)
		throw new Error("Expected Pool datum.");
	const record = outer.fields[0];
	if (
		!(record instanceof Constr) ||
		record.index !== 0 ||
		record.fields.length !== 9
	)
		throw new Error("Malformed PoolDatum.");
	const integer = (i: number) => {
		const value = record.fields[i];
		if (typeof value !== "bigint" || value < 0n) {
			throw new Error("Invalid pool integer.");
		}
		return value;
	};
	const boolean = (i: number) => {
		const value = record.fields[i];
		if (
			!(value instanceof Constr) ||
			value.fields.length !== 0 ||
			(value.index !== 0 && value.index !== 1)
		)
			throw new Error("Invalid pool boolean.");
		return value.index === 1;
	};
	return {
		totalStaked: integer(0),
		rewardDurationSeconds: integer(1),
		periodFinishSeconds: integer(2),
		rewardRate: integer(3),
		lastUpdateSeconds: integer(4),
		rewardPerTokenStored: integer(5),
		accruedLiabilityBound: integer(6),
		isPaused: boolean(7),
		isLocked: boolean(8),
	};
}

/** Normalized vault accounting view; version 2 owner decoding lives in position.ts. */
export type PositionState = PositionRewards & {
	poolId: string;
	positionName: string;
	owner: string;
	payoutAddress: Data;
};
