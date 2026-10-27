import { refId, termsHash } from "@ctvs/protocol";
import { Data, validatorToScriptHash } from "@lucid-evolution/lucid";
import type { ComposedVault } from "../planning/operation.ts";
import {
	setupFactoryPool,
	type FactoryPoolSettings,
} from "../setup/factory-pool.ts";
import { prepareFactoryVault, type FactoryVaultSetup } from "./vault.ts";

/** Pool first, then automatic factory controller; no per-vault approval key. */
export function prepareFactoryDeployment(input: {
	pool: FactoryPoolSettings;
	vault: Omit<FactoryVaultSetup, "poolBinding">;
	positionSeed: FactoryVaultSetup["poolBinding"]["positionSeed"];
}) {
	const pool = setupFactoryPool(input.pool);
	const underlying = input.vault.terms.underlying;
	if (
		input.vault.network !== pool.settings.network ||
		underlying === "ada" ||
		underlying.policy !== pool.settings.stakingAsset.policyId ||
		underlying.name !== pool.settings.stakingAsset.tokenNameHex
	)
		throw Error("Factory pool principal/network mismatch");
	const seeds = [
		refId(input.vault.seed),
		refId(input.positionSeed),
		pool.settings.bootstrapRef.txHash +
			"#" +
			pool.settings.bootstrapRef.outputIndex,
	];
	if (new Set(seeds).size !== 3)
		throw Error("Distinct factory, pool and position seeds required");
	const vault = prepareFactoryVault({
		...input.vault,
		poolBinding: {
			poolPolicy: pool.policy,
			positionSeed: input.positionSeed,
			rewardAsset: {
				policy: pool.settings.rewardAsset.policyId,
				name: pool.settings.rewardAsset.tokenNameHex,
			},
		},
	});
	if (vault.source.policy !== pool.settings.factoryPolicy)
		throw Error("Pool trusts a different factory implementation");
	return {
		schema: "STAKING-CTVS1-FACTORY-DEPLOYMENT-1" as const,
		pool,
		vault,
		stakingIntegrated: false as const,
		deploymentReady: false as const,
		executionEnabled: false as const,
	};
}

/** Adapt only the economic context, never manufacture an authority or a certificate. */
export function factoryOperationContext(
	candidate: ReturnType<typeof prepareFactoryVault>,
): ComposedVault {
	const current = prepareFactoryVault(candidate.input);
	if (
		current.controller !== candidate.controller ||
		current.configHash !== candidate.configHash ||
		current.instanceHash !== candidate.instanceHash ||
		current.source.buildId !== candidate.source.buildId ||
		current.source.policy !== candidate.source.policy ||
		current.source.lock.script !== candidate.source.lock.script ||
		current.script.script !== candidate.script.script ||
		current.certificateUnit !== candidate.certificateUnit ||
		current.configUnit !== candidate.configUnit ||
		current.stateUnit !== candidate.stateUnit ||
		current.address !== candidate.address ||
		Data.to(current.registration) !== Data.to(candidate.registration) ||
		Data.to(current.configData) !== Data.to(candidate.configData) ||
		Data.to(current.stateData) !== Data.to(candidate.stateData)
	)
		throw Error("Stale or altered factory controller preparation");
	return {
		implementation: "staking-v2",
		settings: current.input,
		binding: current.input.poolBinding,
		policy: current.controller,
		termsHash: termsHash(current.input.terms),
		buildId: "factory-staking:" + current.source.buildId,
		genesisPlan: {
			implementation: {
				configLock: validatorToScriptHash(current.source.lock),
			},
		},
	};
}
