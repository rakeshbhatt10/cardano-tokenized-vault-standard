import {
	CML,
	SLOT_CONFIG_NETWORK,
	withCMLScope,
	type Provider,
	type UTxO,
} from "@lucid-evolution/lucid";
import { protocolRef, protocolValue } from "@ctvs/cardano";
import { refId, type OutRef } from "@ctvs/protocol";
import { RecordedEvaluator } from "../../../../../../testing/ledger/evaluator.ts";
import { constructUnsigned } from "../unsigned.ts";
import {
	verifyTransactionEffects,
	type WalletAuthorization,
} from "../ledger/effects/effects.ts";
import type { ComposedPlan } from "../planning/model.ts";
import type { prepareFactoryDeployment } from "./deployment.ts";
import { normalizedUTxO } from "./operation-readback.ts";

export interface FactoryOperationLedger {
	prepared: ReturnType<typeof prepareFactoryDeployment>;
	provider: Provider;
	fundingAddress: string;
	funding: UTxO[];
	collateral: UTxO[];
	protectedInputs: OutRef[];
	maxNetworkFee: bigint;
	maxCollateralExposure: bigint;
}
export const operationEvidence = (u: UTxO) => ({
	ref: protocolRef(u),
	address: u.address,
	value: protocolValue(u.assets),
	referenceScript: u.scriptRef ?? null,
});
const same = (a: unknown, b: unknown) =>
	JSON.stringify(a, (_, v) => (typeof v === "bigint" ? String(v) : v)) ===
	JSON.stringify(b, (_, v) => (typeof v === "bigint" ? String(v) : v));

/** Shared address-only completion: exact effects, final evaluation, minimum ADA,
 * signed-size allowance and collateral against the final fee. Never signs/submits. */
export async function completeFactoryOperation(
	input: FactoryOperationLedger,
	plan: ComposedPlan,
	planned: UTxO[],
	references: UTxO[],
	purposes: { spend: number; mint: number },
) {
	const { provider, fundingAddress } = input;
	const candidate = input.prepared.vault,
		pool = input.prepared.pool;
	const controller = references.find(
		(u) => u.scriptRef?.script === candidate.script.script,
	);
	const staking = references.find(
		(u) => u.scriptRef?.script === pool.script.script,
	);
	if (!controller || !staking)
		throw Error("Exact controller and staking references required");
	const params = await provider.getProtocolParameters();
	const excluded = new Set(
		[
			...input.protectedInputs,
			...planned.map(protocolRef),
			...references.map(protocolRef),
			candidate.input.seed,
		].map(refId),
	);
	const all = [...input.funding, ...input.collateral];
	if (
		!input.funding.length ||
		!input.collateral.length ||
		new Set(all.map((u) => refId(protocolRef(u)))).size !== all.length ||
		all.some(
			(u) =>
				u.address !== fundingAddress ||
				u.datum ||
				u.datumHash ||
				u.scriptRef ||
				excluded.has(refId(protocolRef(u))),
		) ||
		input.collateral.some((u) =>
			Object.keys(u.assets).some((k) => k !== "lovelace"),
		)
	)
		throw Error(
			"Operation funding/collateral is protected, duplicate or invalid",
		);
	const fresh = await provider.getUtxosByOutRef(
		all.map((u) => ({ txHash: u.txHash, outputIndex: u.outputIndex })),
	);
	if (
		fresh.length !== all.length ||
		all.some(
			(u) =>
				!fresh.some((f) => same(operationEvidence(u), operationEvidence(f))),
		)
	)
		throw Error("Operation funding changed");
	// Refresh the entire immutable UTxO snapshot together after the chain-time
	// anchor. Reusing it for balancing/evaluation avoids repeated sequential reads
	// consuming the staking program's short inclusion window. Missing or changed
	// spends/references stop construction; final effects still use exact evidence.
	const wanted = [...planned, ...references, ...all];
	const resolved = await provider.getUtxosByOutRef(
		wanted.map((u) => ({ txHash: u.txHash, outputIndex: u.outputIndex })),
	);
	if (
		resolved.length !== wanted.length ||
		wanted.some(
			(u) => !resolved.some((v) => normalizedUTxO(u) === normalizedUTxO(v)),
		)
	)
		throw Error("Operation input/reference snapshot changed");
	const snapshot = new Map(resolved.map((u) => [refId(protocolRef(u)), u]));
	const constructionProvider = new Proxy(provider, {
		get(target, key) {
			if (key === "getProtocolParameters") return async () => params;
			if (key === "getUtxosByOutRef")
				return async (refs: { txHash: string; outputIndex: number }[]) => {
					const ids = refs.map((r) => r.txHash + "#" + r.outputIndex);
					if (ids.every((id) => snapshot.has(id)))
						return ids.map((id) => structuredClone(snapshot.get(id)!));
					return target.getUtxosByOutRef(refs);
				};
			const value = Reflect.get(target, key);
			return typeof value === "function" ? value.bind(target) : value;
		},
	});
	const slots = SLOT_CONFIG_NETWORK[candidate.input.network];
	const slot = (t: bigint) =>
		(t - BigInt(slots.zeroTime)) / BigInt(slots.slotLength) +
		BigInt(slots.zeroSlot);
	const auth: WalletAuthorization = {
		networkId: 0,
		networkName: candidate.input.network,
		networkDomain: candidate.input.terms.networkDomain,
		planInputs: planned.map(operationEvidence),
		allowedFundingInputs: input.funding.map(operationEvidence),
		allowedCollateralInputs: input.collateral.map(operationEvidence),
		allowedReferenceInputs: references.map(operationEvidence),
		change: { address: fundingAddress, datum: { kind: "none" } },
		maxNetworkFee: input.maxNetworkFee,
		maxCollateralExposure: input.maxCollateralExposure,
		permittedExtraOutputs: [],
		additionalRequiredSigners: [],
		validitySlots: {
			lower: slot(plan.validity!.lowerPosixMs),
			upper: slot(plan.validity!.upperPosixMs),
		},
		slotConfig: {
			zeroTime: BigInt(slots.zeroTime),
			zeroSlot: BigInt(slots.zeroSlot),
			slotLength: BigInt(slots.slotLength),
		},
	};
	const percentage = BigInt(params.collateralPercentage);
	let collateralFloor = 1n;
	for (let attempt = 0; attempt < 3; attempt++) {
		const result = await constructUnsigned(plan, {
			provider: constructionProvider,
			network: candidate.input.network,
			fundingAddress,
			fundingInputs: input.collateral,
			explicitFundingInputs: input.funding,
			collateralLovelace: collateralFloor,
			vaultScript: candidate.script,
			vaultReference: controller,
			stakingScript: pool.script,
			stakingReference: staking,
			authorization: auth,
			evaluator: new RecordedEvaluator(),
		});
		const approval = verifyTransactionEffects(result.cbor, plan, auth);
		const required = (approval.fee * percentage + 99n) / 100n;
		if (approval.collateralExposure < required) {
			collateralFloor = required;
			if (required > input.maxCollateralExposure)
				throw Error("Operation collateral exceeds approved exposure");
			continue;
		}
		if (
			!result.finalEvaluation ||
			result.effects.redeemers.length !== purposes.spend + purposes.mint ||
			result.effects.redeemers.filter((r) => r.purpose === "spend").length !==
				purposes.spend ||
			result.effects.redeemers.filter((r) => r.purpose === "mint").length !==
				purposes.mint
		)
			throw Error("All operation purposes must evaluate");
		const minimumAda = withCMLScope((own) => {
			const outputs = own(
				own(own(CML.Transaction.from_cbor_hex(result.cbor)).body()).outputs(),
			);
			return Array.from({ length: outputs.len() }, (_, index) => {
				const o = own(outputs.get(index)),
					actual = own(o.amount()).coin(),
					min = CML.min_ada_required(o, params.coinsPerUtxoByte);
				if (actual < min) throw Error("Operation output below minimum ADA");
				return {
					index,
					actualLovelace: String(actual),
					minimumLovelace: String(min),
				};
			});
		});
		return {
			...result,
			plan,
			approval,
			authorization: auth,
			feeLovelace: String(approval.fee),
			minimumAda,
			collateralCheck: {
				percentage: String(percentage),
				requiredLovelace: String(required),
				exposureLovelace: String(approval.collateralExposure),
			},
		};
	}
	throw Error("Operation collateral/fee did not converge");
}
