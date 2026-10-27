import {
	Data,
	calculateMinLovelaceFromUTxO,
	getAddressDetails,
} from "@lucid-evolution/lucid";
import { ledgerValue, protocolRef, protocolValue } from "@ctvs/cardano";
import {
	assetId,
	decodeData,
	encodeData,
	enterprise,
	hex,
	refId,
	stateFromData,
	transition,
	preview,
	type OutRef,
} from "@ctvs/protocol";
import type { SyncDeployment, ProtectedInput } from "@ctvs/planning";
import { factoryOperationContext } from "./deployment.ts";
import { setupFactoryPool } from "../setup/factory-pool.ts";
import { buildComposedPlan, positionName } from "../planning/operation.ts";
import { plannedAddress } from "../ledger/effects/effects-ledger.ts";
import { decodePoolDatum } from "../staking/datum.ts";
import { decodeVaultPosition } from "../staking/position.ts";
import { previewClaim } from "../staking/rewards.ts";
import {
	completeFactoryOperation,
	type FactoryOperationLedger,
} from "./operation-completion.ts";

export interface FactoryPositionLedger extends FactoryOperationLedger {
	configRef: OutRef;
	controllerReference: OutRef;
	stakingReference: OutRef;
	lowerBoundMs: bigint;
	/** Operational clients may select chain time after resolving inputs, before quoting. */
	selectLowerBoundMs?: () => Promise<bigint>;
	reserveBuffer: bigint;
}

export interface FactoryPositionOperationInput extends FactoryPositionLedger {
	operation: "deposit" | "mint" | "withdraw" | "redeem";
	/** Deposit/withdraw use principal base units; redeem uses SHARE base units. */
	amount: bigint;
	/** Minimum shares/assets on deposit/redeem; maximum shares on withdraw. */
	bound?: bigint;
	maxRewardInput?: bigint;
}

/** Existing-position transaction: immutable identity, economic quote and exact
 * staking action are coupled; registration is only required on first entry. */
export async function constructFactoryPositionOperation(
	input: FactoryPositionOperationInput,
) {
	const operation = input.operation,
		entering = operation === "deposit" || operation === "mint";
	const { provider, fundingAddress } = input;
	const { vault: candidate, pool } = input.prepared;
	const vault = factoryOperationContext(candidate),
		checkedPool = setupFactoryPool(pool.settings);
	if (
		checkedPool.policy !== pool.policy ||
		checkedPool.script.script !== pool.script.script ||
		pool.policy !== vault.binding.poolPolicy
	)
		throw Error("Redeem pool/source binding mismatch");
	if (
		input.amount <= 0n ||
		input.reserveBuffer < 0n ||
		input.reserveBuffer > 1_000_000n
	)
		throw Error(
			"Positive operation amount and zero-to-one-ADA storage buffer required",
		);
	const address = getAddressDetails(fundingAddress);
	if (address.networkId !== 0 || address.paymentCredential?.type !== "Key")
		throw Error("Testnet key receiver required");
	const resolve = async (r: OutRef) => {
		const found = await provider.getUtxosByOutRef([
			{ txHash: r.txId, outputIndex: Number(r.index) },
		]);
		if (
			found.length !== 1 ||
			!found[0] ||
			refId(protocolRef(found[0])) !== refId(r)
		)
			throw Error("Redeem input/reference missing or substituted");
		return found[0];
	};
	const marker = pool.policy + positionName(vault.binding.positionSeed);
	const [state, poolInput, positions, config, controller, staking] =
		await Promise.all([
			provider.getUtxoByUnit(candidate.stateUnit),
			provider.getUtxoByUnit(pool.poolUnit),
			provider.getUtxosWithUnit(pool.address, marker),
			resolve(input.configRef),
			resolve(input.controllerReference),
			resolve(input.stakingReference),
		]);
	if (positions.length !== 1 || !positions[0]?.datum)
		throw Error("Exactly one authenticated existing position required");
	const positionInput = positions[0];
	if (
		controller.scriptRef?.script !== candidate.script.script ||
		staking.scriptRef?.script !== pool.script.script
	)
		throw Error("Exact deployed controller/staking reference required");
	if (
		!config.datum ||
		config.scriptRef ||
		config.address !== candidate.source.lockAddress ||
		config.assets[candidate.configUnit] !== 1n ||
		Object.keys(config.assets).length !== 2 ||
		config.assets.lovelace !== candidate.input.configReserve ||
		Data.to(Data.from(config.datum)) !== Data.to(candidate.configData)
	)
		throw Error("Immutable Config identity/commitment mismatch");
	if (
		!state.datum ||
		state.scriptRef ||
		state.address !== candidate.address ||
		state.assets[candidate.stateUnit] !== 1n
	)
		throw Error("Authenticated controller State required");
	const core = stateFromData(decodeData(state.datum));
	const quote = preview(operation, input.amount, core, vault.settings.terms);
	const bound =
		input.bound ??
		(operation === "mint"
			? quote.grossAssets
			: operation === "withdraw"
			? quote.shares
			: operation === "redeem"
				? quote.netAssets
				: quote.shares);
	transition(operation, input.amount, bound, core, vault.settings.terms);
	if (!entering && quote.shares > core.economicSupply)
		throw Error("Exit exceeds economic supply");
	const underlying = vault.settings.terms.underlying;
	if (underlying === "ada") throw Error("Native principal required");
	const fundingUnit = entering
		? underlying.policy + underlying.name
		: candidate.controller + "5348415245";
	const required = entering ? quote.grossAssets : quote.shares;
	if (
		input.funding.reduce((n, u) => n + (u.assets[fundingUnit] ?? 0n), 0n) <
		required
	)
		throw Error(
			entering
				? "Authorized inputs do not cover principal deposit"
				: "Authorized wallet inputs do not cover the share burn",
		);
	const lowerBoundMs = input.selectLowerBoundMs
		? await input.selectLowerBoundMs()
		: input.lowerBoundMs;
	const earned = previewClaim(
		decodePoolDatum(poolInput.datum!),
		decodeVaultPosition(positionInput.datum!, candidate.controller),
		lowerBoundMs / 1000n,
	).rewardAmount;
	const oldRewards =
		protocolValue(state.assets)[assetId(vault.binding.rewardAsset)] ?? 0n;
	const rewardBound = entering
		? 0n
		: ((oldRewards + earned) * quote.shares) / core.economicSupply;
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
	const args = {
		vault,
		deployment,
		stateInput,
		poolInput,
		positionInput,
		operation,
		amount: input.amount,
		bound,
		receiver,
		receiverTopup: 1_000_000n,
		positionReserve: positionInput.assets.lovelace!,
		poolTopup: 0n,
		lowerBoundMs,
		validityWindowMs: 60_000n,
		maxRewardInput: entering ? (input.maxRewardInput ?? 0n) : 0n,
		minRewardOutput: rewardBound,
	};
	const params = await provider.getProtocolParameters();
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
	for (let i = 0; i < 3; i++) {
		const p = buildComposedPlan(args);
		args.receiverTopup = minimum(p.outputs[1]!) + input.reserveBuffer;
		const poolReserve = minimum(p.outputs[2]!) + input.reserveBuffer;
		args.poolTopup =
			poolReserve > poolInput.assets.lovelace!
				? poolReserve - poolInput.assets.lovelace!
				: 0n;
	}
	const plan = buildComposedPlan(args);
	const result = await completeFactoryOperation(
		input,
		plan,
		[state, poolInput, positionInput],
		[config, controller, staking],
		{ spend: 3, mint: 1 },
	);
	return {
		...result,
		economicEffects: plan.economicEffects,
		rewardEffects: plan.rewardEffects,
		storage: {
			receiver: args.receiverTopup,
			poolTopup: args.poolTopup,
			retainedPosition: positionInput.assets.lovelace,
		},
		snapshots: {
			state,
			pool: poolInput,
			position: positionInput,
			references: [config, controller, staking],
			funding: input.funding,
			collateral: input.collateral,
		},
		fullRedemption: !entering && quote.shares === core.economicSupply,
	};
}
