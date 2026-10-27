import type { ChainPoint } from "@ctvs/planning";
import { assetData,bytes,constr,outRefData,type Asset,type OutRef,type Terms } from "@ctvs/protocol";
export interface PoolBinding {
	poolPolicy: string;
	positionSeed: OutRef;
	rewardAsset: Exclude<Asset, "ada">;
}
export interface VaultIdentitySetup {
	network: "Preview" | "Preprod";
	terms: Terms;
	seed: OutRef;
	configReserve: bigint;
	stateReserve: bigint;
	chainPoint: ChainPoint;
}
export interface VaultSetup extends VaultIdentitySetup {
	poolBinding: PoolBinding;
}
export const poolBindingData = (b: PoolBinding) =>
	constr(0, [
		bytes(b.poolPolicy, 28),
		outRefData(b.positionSeed),
		assetData(b.rewardAsset),
	]);

