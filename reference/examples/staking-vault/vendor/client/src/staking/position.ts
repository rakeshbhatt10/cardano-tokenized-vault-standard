import { Constr, Data } from "@lucid-evolution/lucid";
import type { PositionState } from "./datum.ts";

export type PositionOwner =
	| { kind: "wallet"; keyHash: string }
	| {
			kind: "vault";
			controller: string;
			statePolicy: string;
			stateName: string;
	  };
export type StakingPositionState = Omit<PositionState, "owner"> & {
	schemaVersion: 2n;
	owner: PositionOwner;
};
const hash = (v: Data, bytes: number) => {
	if (typeof v !== "string" || !new RegExp(`^[0-9a-f]{${bytes * 2}}$`).test(v))
		throw new Error("Invalid staking owner identity");
	return v;
};
const record = (v: Data, index: number, length: number): Data[] => {
	if (!(v instanceof Constr) || v.index !== index || v.fields.length !== length)
		throw new Error("Invalid version 2 staking record");
	return v.fields;
};
export function ownerData(owner: PositionOwner): Data {
	if (owner.kind === "wallet") return new Constr(0, [hash(owner.keyHash, 28)]);
	if (!/^(?:[0-9a-f]{2}){0,32}$/.test(owner.stateName))
		throw new Error("Invalid State asset name");
	return new Constr(1, [
		hash(owner.controller, 28),
		hash(owner.statePolicy, 28),
		owner.stateName,
	]);
}
export function decodeOwner(raw: Data): PositionOwner {
	if (raw instanceof Constr && raw.index === 0) {
		const [key] = record(raw, 0, 1);
		return { kind: "wallet", keyHash: hash(key!, 28) };
	}
	const [controller, statePolicy, stateName] = record(raw, 1, 3);
	if (
		typeof stateName !== "string" ||
		!/^(?:[0-9a-f]{2}){0,32}$/.test(stateName)
	)
		throw new Error("Invalid State asset name");
	return {
		kind: "vault",
		controller: hash(controller!, 28),
		statePolicy: hash(statePolicy!, 28),
		stateName,
	};
}
export function decodePosition(cbor: string): StakingPositionState {
	const [raw] = record(Data.from(cbor), 1, 1);
	const f = record(raw!, 0, 8);
	if (f[0] !== 2n) throw new Error("Unsupported position schema version");
	const quantity = (i: number) => {
		const q = f[i];
		if (typeof q !== "bigint" || q < 0n)
			throw new Error("Invalid position quantity");
		return q;
	};
	const result: StakingPositionState = {
		schemaVersion: 2n,
		poolId: hash(f[1]!, 28),
		positionName: hash(f[2]!, 32),
		owner: decodeOwner(f[3]!),
		payoutAddress: f[4]!,
		stakedAmount: quantity(5),
		rewardPerTokenPaid: quantity(6),
		pendingRewards: quantity(7),
	};
	// The controller's exact custody address is enforced separately; validate Data shape here.
	record(result.payoutAddress, 0, 2);
	return result;
}
export function encodePosition(p: StakingPositionState): string {
	const cbor = Data.to(
		new Constr(1, [
			new Constr(0, [
				p.schemaVersion,
				p.poolId,
				p.positionName,
				ownerData(p.owner),
				p.payoutAddress,
				p.stakedAmount,
				p.rewardPerTokenPaid,
				p.pendingRewards,
			]),
		]),
	);
	decodePosition(cbor);
	return cbor;
}
export const vaultOwner = (policy: string): PositionOwner => ({
	kind: "vault",
	controller: policy,
	statePolicy: policy,
	stateName: "5354415445",
});
export function decodeVaultPosition(
	cbor: string,
	policy: string,
): PositionState {
	const p = decodePosition(cbor),
		o = p.owner;
	if (
		o.kind !== "vault" ||
		o.controller !== policy ||
		o.statePolicy !== policy ||
		o.stateName !== "5354415445"
	)
		throw new Error(
			"Position does not belong to the expected vault State identity",
		);
	const expected = new Constr(0, [new Constr(1, [policy]), new Constr(1, [])]);
	if (Data.to(p.payoutAddress) !== Data.to(expected))
		throw new Error("Vault position custody address changed");
	return { ...p, owner: policy };
}
export function encodeVaultPosition(p: PositionState): string {
	return encodePosition({
		...p,
		schemaVersion: 2n,
		owner: vaultOwner(p.owner),
	});
}
export function openPosition(
	seed: { txId: string; index: bigint },
	policy: string,
): Data {
	if (seed.index < 0n || seed.index > 4294967295n)
		throw new Error("Invalid position seed index");
	return new Constr(1, [
		2n,
		new Constr(0, [hash(seed.txId, 32), seed.index]),
		ownerData(vaultOwner(policy)),
	]);
}
