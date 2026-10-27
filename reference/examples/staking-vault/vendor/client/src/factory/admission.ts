import { protocolRef } from "@ctvs/cardano";
import { decodeData, refId, type OutRef } from "@ctvs/protocol";
import {
	Data,
	validatorToAddress,
	type Provider,
	type UTxO,
} from "@lucid-evolution/lucid";
import { decodeAuthorization } from "../../protocol/shared-v1/authorization.ts";
import { decodeRegistration } from "../../protocol/shared-v1/registration.ts";
import { validateComposedPlan, type ComposedPlan } from "../planning/model.ts";
import {
	setupFactoryPool,
	type PreparedFactoryPool,
} from "../setup/factory-pool.ts";
import { factoryOperationContext } from "./deployment.ts";
import type { prepareFactoryVault } from "./vault.ts";

/** First-entry reference validation only. Existing-position operations never depend on a registry lookup. */
export async function resolveFactoryAdmission(input: {
	plan: ComposedPlan;
	candidate: ReturnType<typeof prepareFactoryVault>;
	pool: PreparedFactoryPool;
	provider: Pick<Provider, "getUtxosByOutRef">;
	configRef: OutRef;
	certificateRef: OutRef;
}) {
	const { plan, candidate, provider, configRef, certificateRef } = input;
	validateComposedPlan(plan);
	const context = factoryOperationContext(candidate);
	const pool = setupFactoryPool(input.pool.settings);
	if (
		pool.inputHash !== input.pool.inputHash ||
		pool.script.script !== input.pool.script.script ||
		pool.policy !== input.pool.policy
	)
		throw Error("Altered factory pool preparation");
	if (
		pool.settings.factoryPolicy !== candidate.source.policy ||
		pool.policy !== candidate.input.poolBinding.poolPolicy ||
		pool.settings.network !== candidate.input.network ||
		plan.implementation.policy !== context.policy ||
		plan.implementation.buildId !== context.buildId ||
		plan.implementation.configLock !==
			context.genesisPlan.implementation.configLock ||
		plan.implementation.termsHash !== context.termsHash ||
		plan.network.name !== candidate.input.network ||
		plan.network.domain !== candidate.input.terms.networkDomain
	)
		throw Error("Factory admission controller/pool binding mismatch");
	if (
		candidate.input.terms.underlying === "ada" ||
		candidate.input.terms.underlying.policy !==
			pool.settings.stakingAsset.policyId ||
		candidate.input.terms.underlying.name !==
			pool.settings.stakingAsset.tokenNameHex ||
		candidate.input.poolBinding.rewardAsset.policy !==
			pool.settings.rewardAsset.policyId ||
		candidate.input.poolBinding.rewardAsset.name !==
			pool.settings.rewardAsset.tokenNameHex
	)
		throw Error("Factory admission asset binding mismatch");
	const state = plan.inputs.find((i) => i.role === "state");
	if (plan.stateAuthorization !== "shared-v1" || !state?.redeemer)
		throw Error("Shared consumed State approval required");
	const action = decodeAuthorization(state.redeemer);
	if (
		action.kind !== "staking" ||
		action.operation !== "stake" ||
		!action.creationRef ||
		refId(action.creationRef) !==
			refId(candidate.input.poolBinding.positionSeed) ||
		action.poolId !== pool.policy
	)
		throw Error(
			"Factory admission is only required for exact first position creation",
		);
	const configId = refId(configRef),
		certificateId = refId(certificateRef);
	if (
		configId === certificateId ||
		plan.inputs.some((i) => [configId, certificateId].includes(refId(i.ref))) ||
		plan.referenceInputs.filter((r) => refId(r) === configId).length !== 1 ||
		plan.referenceInputs.some((r) => refId(r) === certificateId)
	)
		throw Error(
			"Distinct unconsumed certificate and Config references required",
		);
	const resolve = async (ref: OutRef): Promise<UTxO> => {
		const found = await provider.getUtxosByOutRef([
			{ txHash: ref.txId, outputIndex: Number(ref.index) },
		]);
		if (
			found.length !== 1 ||
			!found[0] ||
			refId(protocolRef(found[0])) !== refId(ref)
		)
			throw Error("Admission reference missing, spent or substituted");
		return found[0];
	};
	const [certificate, config] = await Promise.all([
		resolve(certificateRef),
		resolve(configRef),
	]);
	const lockAddress = validatorToAddress(
		candidate.input.network,
		candidate.source.lock,
	);
	const exact = (u: UTxO, unit: string, expected: Data) => {
		if (
			u.address !== lockAddress ||
			u.scriptRef ||
			!u.datum ||
			u.assets[unit] !== 1n ||
			Data.to(Data.from(u.datum)) !== Data.to(expected)
		)
			throw Error("Unauthenticated or changed factory reference");
		return u.datum;
	};
	const certificateDatum = exact(
		certificate,
		candidate.certificateUnit,
		candidate.registration,
	);
	exact(config, candidate.configUnit, candidate.configData);
	const registration = decodeRegistration(decodeData(certificateDatum));
	if (
		registration.controller !== context.policy ||
		registration.instanceHash !== candidate.instanceHash ||
		registration.configHash !== candidate.configHash
	)
		throw Error("Registration commitment mismatch");
	const result = validateComposedPlan({
		...structuredClone(plan),
		referenceInputs: [...plan.referenceInputs, certificateRef],
	});
	return {
		plan: result,
		references: [config, certificate],
		registration: {
			...registration,
			factoryPolicy: pool.settings.factoryPolicy,
			configRef,
			certificateRef,
		},
		referenceEvidenceVerified: true as const,
		stakingIntegrated: false as const,
		deploymentReady: false as const,
		executionEnabled: false as const,
	};
}
