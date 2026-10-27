import { buildGenesisPlan } from "../../../../../../implementations/ctvs1/client/src/genesis.ts";
import { decodeData, termsHash, enterprise } from "@ctvs/protocol";
import {
	Constr,
	Data,
	validatorToScriptHash,
	type UTxO,
} from "@lucid-evolution/lucid";
import { factoryOperationContext } from "./deployment.ts";
import type { prepareFactoryVault } from "./vault.ts";
import type { FactoryGenesisReferences } from "./genesis-builder.ts";
import { validateComposedPlan, type ComposedPlan } from "../planning/model.ts";

/** Trusted intent used to independently inspect every final genesis effect. */
export function factoryGenesisPlan(
	vault: ReturnType<typeof prepareFactoryVault>,
	refs: FactoryGenesisReferences,
	certificateReserve: bigint,
): ComposedPlan {
	factoryOperationContext(vault);
	const ref = (u: UTxO) => ({ txId: u.txHash, index: BigInt(u.outputIndex) });
	const base = buildGenesisPlan({
		...vault.input,
		deployment: {
			family: "ctvs1",
			network: vault.input.network,
			networkDomain: vault.input.terms.networkDomain,
			policy: vault.controller,
			configLock: validatorToScriptHash(vault.source.lock),
			claimScript: null,
			termsHash: termsHash(vault.input.terms),
			configRef: vault.input.seed,
			buildId: "factory-staking:" + vault.source.buildId,
			chainPoint: vault.input.chainPoint,
		},
	});
	return validateComposedPlan({
		...base,
		schema: "STAKING-CTVS1-PLAN-1",
		factoryGenesis: {
			policy: vault.source.policy,
			instance: decodeData(Data.to(vault.instance)),
			prefix0: ref(refs.prefix0),
			prefix1: ref(refs.prefix1),
		},
		referenceInputs: [ref(refs.factory), ref(refs.prefix0), ref(refs.prefix1)],
		outputs: [
			{ ...base.outputs[0]!, datum: decodeData(Data.to(vault.configData)) },
			{ ...base.outputs[1]!, datum: decodeData(Data.to(vault.stateData)) },
			{
				index: 2n,
				role: "registration",
				address: enterprise(base.implementation.configLock),
				datum: decodeData(Data.to(vault.registration)),
				datumMode: "inline",
				referenceScript: null,
				value: {
					ada: certificateReserve,
					[vault.source.policy + "." + vault.controller]: 1n,
				},
			},
		],
		mint: [
			...base.mint,
			{
				policy: vault.source.policy,
				assets: { [vault.controller]: 1n },
				redeemer: decodeData(
					Data.to(
						new Constr(0, [
							vault.instance,
							new Constr(0, [
								refs.prefix0.txHash,
								BigInt(refs.prefix0.outputIndex),
							]),
							new Constr(0, [
								refs.prefix1.txHash,
								BigInt(refs.prefix1.outputIndex),
							]),
							0n,
							1n,
							2n,
						]),
					),
				),
			},
		],
	});
}
