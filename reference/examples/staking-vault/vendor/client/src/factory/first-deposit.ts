import { completeFactoryOperation } from "./operation-completion.ts";
import {
	getAddressDetails,
	calculateMinLovelaceFromUTxO,
	type Provider,
	type UTxO,
} from "@lucid-evolution/lucid";
import { ledgerValue, protocolRef, protocolValue } from "@ctvs/cardano";
import {
	decodeData,
	encodeData,
	enterprise,
	hex,
	refId,
	stateFromData,
	transition,
	type OutRef,
} from "@ctvs/protocol";
import type { ProtectedInput, SyncDeployment } from "@ctvs/planning";
import { plannedAddress } from "../ledger/effects/effects-ledger.ts";
import { buildComposedPlan, positionName } from "../planning/operation.ts";
import {
	factoryOperationContext,
	type prepareFactoryDeployment,
} from "./deployment.ts";
import { resolveFactoryAdmission } from "./admission.ts";

export interface FirstDepositLedger {
	prepared: ReturnType<typeof prepareFactoryDeployment>;
	provider: Provider;
	fundingAddress: string;
	funding: UTxO[];
	collateral: UTxO[];
	protectedInputs: OutRef[];
	configRef: OutRef;
	certificateRef: OutRef;
	controllerReference: OutRef;
	stakingReference: OutRef;
	amount: bigint;
	lowerBoundMs: bigint;
	reserveBuffer: bigint;
	maxNetworkFee: bigint;
	maxCollateralExposure: bigint;
}
export { operationEvidence as depositEvidence } from "./operation-completion.ts";
/** First entry only. Chain-authenticated identities precede arithmetic and wallet intent. */
export async function constructFactoryFirstDeposit(input: FirstDepositLedger) {
	const { prepared, provider, fundingAddress } = input;
	const { vault: candidate, pool } = prepared;
	const vault = factoryOperationContext(candidate);
	if (
		input.amount <= 0n ||
		input.reserveBuffer < 0n ||
		input.reserveBuffer > 1_000_000n
	)
		throw Error(
			"Positive principal and storage buffer between zero and one ADA required",
		);
	const address = getAddressDetails(fundingAddress);
	if (address.networkId !== 0 || address.paymentCredential?.type !== "Key")
		throw Error("Testnet key funding wallet required");
	const resolve = async (r: OutRef) => {
		const found = await provider.getUtxosByOutRef([
			{ txHash: r.txId, outputIndex: Number(r.index) },
		]);
		if (
			found.length !== 1 ||
			!found[0] ||
			refId(protocolRef(found[0])) !== refId(r)
		)
			throw Error("Deposit input/reference missing or substituted");
		return found[0];
	};
	const [state, poolInput, creationInput, controller, staking] =
		await Promise.all([
			provider.getUtxoByUnit(candidate.stateUnit),
			provider.getUtxoByUnit(pool.poolUnit),
			resolve(vault.binding.positionSeed),
			resolve(input.controllerReference),
			resolve(input.stakingReference),
		]);
	if (
		controller.scriptRef?.script !== candidate.script.script ||
		staking.scriptRef?.script !== pool.script.script
	)
		throw Error("Exact deployed controller/staking reference required");
	if (
		creationInput.address !== fundingAddress ||
		creationInput.datum ||
		creationInput.datumHash ||
		creationInput.scriptRef ||
		Object.keys(creationInput.assets).some((u) => u !== "lovelace")
	)
		throw Error(
			"Position seed must be a clean input owned by the funding wallet",
		);
	if (
		!state.datum ||
		state.scriptRef ||
		state.address !== candidate.address ||
		state.assets[candidate.stateUnit] !== 1n
	)
		throw Error("Authenticated controller State required");
	const core = stateFromData(decodeData(state.datum));
	if (
		core.backingAssets !== 0n ||
		core.economicSupply !== 0n ||
		core.accruedFees !== 0n
	)
		throw Error("First deposit requires an empty vault");
	const positions = await provider.getUtxosWithUnit(
		pool.address,
		pool.policy + positionName(vault.binding.positionSeed),
	);
	if (positions.length)
		throw Error("Position already exists; use the top-up flow");
	const stateInput: ProtectedInput = {
		ref: protocolRef(state),
		address: enterprise(vault.policy),
		datum: decodeData(state.datum),
		datumMode: "inline",
		referenceScript: null,
		value: protocolValue(state.assets),
	};
	const deployment: SyncDeployment = {
		family: "ctvs1",
		network: vault.settings.network,
		networkDomain: vault.settings.terms.networkDomain,
		policy: vault.policy,
		configLock: vault.genesisPlan.implementation.configLock,
		claimScript: null,
		termsHash: vault.termsHash,
		configRef: input.configRef,
		buildId: vault.buildId,
		chainPoint: vault.settings.chainPoint,
	};
	const receiver = {
		address: {
			payment: { type: "key" as const, hash: address.paymentCredential.hash },
			stake: address.stakeCredential
				? {
						type:
							address.stakeCredential.type === "Key"
								? ("key" as const)
								: ("script" as const),
						hash: address.stakeCredential.hash,
					}
				: null,
		},
		datum: null,
	};
	const bound = transition(
		"deposit",
		input.amount,
		1n,
		core,
		vault.settings.terms,
	).quote.shares;
	const params = await provider.getProtocolParameters();
	const args = {
		vault,
		deployment,
		stateInput,
		poolInput,
		creationInput,
		operation: "deposit" as const,
		amount: input.amount,
		bound,
		receiver,
		receiverTopup: 1_000_000n,
		positionReserve: 1_000_000n,
		poolTopup: 0n,
		lowerBoundMs: input.lowerBoundMs,
		maxRewardInput: 0n,
		minRewardOutput: 0n,
	};
	const minimum = (
		o: ReturnType<typeof buildComposedPlan>["outputs"][number],
	) =>
		calculateMinLovelaceFromUTxO(params.coinsPerUtxoByte, {
			txHash: "00".repeat(32),
			outputIndex: 0,
			address: plannedAddress(o.address, 0),
			assets: ledgerValue(o.value),
			...(o.datum === null ? {} : { datum: hex(encodeData(o.datum)) }),
		});
	// Iterate integer-width effects before freezing intent; no implicit balancer padding.
	for (let i = 0; i < 3; i++) {
		const p = buildComposedPlan(args);
		args.receiverTopup = minimum(p.outputs[1]!) + input.reserveBuffer;
		args.positionReserve = minimum(p.outputs[3]!) + input.reserveBuffer;
		const poolReserve = minimum(p.outputs[2]!) + input.reserveBuffer;
		args.poolTopup =
			poolReserve > poolInput.assets.lovelace!
				? poolReserve - poolInput.assets.lovelace!
				: 0n;
	}
	const basePlan = buildComposedPlan(args);
	if (basePlan.outputs[0]!.value.ada! < minimum(basePlan.outputs[0]!))
		throw Error(
			"Existing State storage insufficient; separate maintenance required",
		);
	const admission = await resolveFactoryAdmission({
		plan: basePlan,
		candidate,
		pool,
		provider,
		configRef: input.configRef,
		certificateRef: input.certificateRef,
	});
	const plan = admission.plan;
	const result = await completeFactoryOperation(
		input,
		plan,
		[state, poolInput, creationInput],
		[...admission.references, controller, staking],
		{ spend: 2, mint: 2 },
	);
	return {
		...result,
		economicEffects: basePlan.economicEffects,
		rewardEffects: basePlan.rewardEffects,
		storage: {
			receiver: args.receiverTopup,
			position: args.positionReserve,
			poolTopup: args.poolTopup,
		},
		snapshots: {
			state,
			pool: poolInput,
			creationInput,
			references: [...admission.references, controller, staking],
			funding: input.funding,
			collateral: input.collateral,
		},
	};
}
