import { getAddressDetails } from "@lucid-evolution/lucid";

export interface PoolSettings {
	network: "Preview" | "Preprod";
	sourcePool: "test1-test2" | "tokenc-test2" | "test2-test1" | "custom";
	bootstrapRef: { txHash: string; outputIndex: string };
	manager: string;
	rewardsDistributor: string;
	fundingAddress: string;
	stakingAsset: { policyId: string; tokenNameHex: string };
	rewardAsset: { policyId: string; tokenNameHex: string };
	poolReserveLovelace: string;
	referenceReserveLovelace: string;
}

function object(value: unknown, keys: string[]): Record<string, unknown> {
	if (
		!value ||
		typeof value !== "object" ||
		Array.isArray(value) ||
		Object.keys(value).sort().join(",") !== keys.slice().sort().join(",")
	)
		throw new Error(
			"Exact public pool settings required; unknown or missing fields",
		);
	return value as Record<string, unknown>;
}
function hex(value: unknown, bytes: number) {
	if (
		typeof value !== "string" ||
		!new RegExp(`^[0-9a-f]{${bytes * 2}}$`).test(value)
	)
		throw new Error("Explicit lowercase hex identity required");
	return value;
}
function name(value: unknown) {
	if (typeof value !== "string" || !/^(?:[0-9a-f]{2}){0,32}$/.test(value))
		throw new Error("Asset name must be at most 32 bytes of lowercase hex");
	return value;
}
function asset(value: unknown) {
	const a = object(value, ["policyId", "tokenNameHex"]);
	return { policyId: hex(a.policyId, 28), tokenNameHex: name(a.tokenNameHex) };
}
function quantity(value: unknown, positive = true) {
	if (
		typeof value !== "string" ||
		!/^(0|[1-9][0-9]{0,19})$/.test(value) ||
		BigInt(value) > (1n << 63n) - 1n ||
		(positive && BigInt(value) === 0n)
	)
		throw new Error("Explicit canonical integer quantity required");
	return value;
}
/** Public configuration only. Native assets on testnets must be specified, never copied from Mainnet implicitly. */
export function readPoolSettings(value: unknown): PoolSettings {
	const v = object(value, [
		"network",
		"sourcePool",
		"bootstrapRef",
		"manager",
		"rewardsDistributor",
		"fundingAddress",
		"stakingAsset",
		"rewardAsset",
		"poolReserveLovelace",
		"referenceReserveLovelace",
	]);
	if (v.network !== "Preview" && v.network !== "Preprod")
		throw new Error("Staking example requires explicit Preview or Preprod");
	if (
		v.sourcePool !== "test1-test2" &&
		v.sourcePool !== "tokenc-test2" &&
		v.sourcePool !== "test2-test1" &&
		v.sourcePool !== "custom"
	)
		throw new Error("Choose an explicit native-token pool profile");
	const ref = object(v.bootstrapRef, ["txHash", "outputIndex"]);
	const index = quantity(ref.outputIndex, false);
	if (BigInt(index) > 4294967295n)
		throw new Error("Bootstrap index exceeds ledger range");
	const manager = hex(v.manager, 28);
	if (typeof v.fundingAddress !== "string")
		throw new Error("Explicit funding address required");
	const address = getAddressDetails(v.fundingAddress);
	if (
		address.networkId !== 0 ||
		address.paymentCredential?.type !== "Key" ||
		address.paymentCredential.hash !== manager
	)
		throw new Error(
			"Funding must be a testnet key address controlled by the explicit manager",
		);
	const stakingAsset = asset(v.stakingAsset),
		rewardAsset = asset(v.rewardAsset);
	if (
		stakingAsset.policyId + stakingAsset.tokenNameHex ===
		rewardAsset.policyId + rewardAsset.tokenNameHex
	)
		throw new Error("Distinct principal and reward assets are required");
	return {
		network: v.network,
		sourcePool: v.sourcePool,
		bootstrapRef: { txHash: hex(ref.txHash, 32), outputIndex: index },
		manager,
		rewardsDistributor: hex(v.rewardsDistributor, 28),
		fundingAddress: v.fundingAddress,
		stakingAsset,
		rewardAsset,
		poolReserveLovelace: quantity(v.poolReserveLovelace),
		referenceReserveLovelace: quantity(v.referenceReserveLovelace),
	};
}
