import type { WalletAuthorization } from "@ctvs/cardano";
import { verifyTransactionEffects } from "./ledger/effects/effects.ts";
import {
	validateComposedPlan as validatePlan,
	type ComposedPlan as TransactionPlan,
} from "./planning/model.ts";
import {
	CML,
	type EvaluationInput,
	type EvaluatorAdapter,
	Lucid,
	type Network,
	type Provider,
	type Script,
	type UTxO,
	validatorToScriptHash,
	withCMLScope,
} from "@lucid-evolution/lucid";
import { checkFinalBudgets } from "../support/evaluation.ts";
import { buildPlanTransaction, safeTime } from "./ledger/builder.ts";

export interface UnsignedOptions {
	provider: Provider;
	network: Network;
	fundingAddress: string;
	fundingInputs: UTxO[];
	/** Explicit key inputs for fees/assets, separate from the wallet's collateral candidates. */
	explicitFundingInputs?: UTxO[];
	/** Explicit collateral floor for a separately approved collateral wallet set. */
	collateralLovelace?: bigint;
	vaultScript: Script;

	vaultReference?: UTxO;
	stakingScript?: Script;
	stakingReference?: UTxO;
	authorization: WalletAuthorization;
	evaluator: EvaluatorAdapter;
}

/** Builds/evaluates bytes using an address-only wallet; returns no signer or submitter. Provider evidence is caller-trusted. */
export async function constructUnsigned(
	plan: TransactionPlan,
	options: UnsignedOptions,
) {
	validatePlan(plan);

	if (
		plan.implementation.family !== "ctvs1" ||
		plan.implementation.wire !== 2 ||
		plan.implementation.profile !== 0
	)
		throw new Error("Require CTVS-1 WIRE-2 profile 0");

	if (
		options.network !== plan.network.name ||
		options.authorization.networkName !== plan.network.name ||
		options.authorization.networkDomain !== plan.network.domain
	)
		throw new Error("Construction network binding mismatch");

	if (
		validatorToScriptHash(options.vaultScript) !== plan.implementation.policy ||
		plan.implementation.claimScript !== null
	)
		throw new Error("Script identity mismatch");

	let captured: EvaluationInput | undefined;
	const evaluator: EvaluatorAdapter = {
		evaluate: async (input) => {
			const result = await options.evaluator.evaluate(input);

			captured = input;

			return result;
		},
	};
	const slots = options.authorization.slotConfig;
	const provider = new Proxy(options.provider, {
		get(target, key) {
			if (key === "submitTx")
				return () => {
					throw new Error("Staking vault submission disabled");
				};
			const value = Reflect.get(target, key);
			return typeof value === "function" ? value.bind(target) : value;
		},
	});
	const lucid = await Lucid(provider, options.network, {
		evaluator,
		slotConfig: {
			zeroTime: safeTime(slots.zeroTime),
			zeroSlot: safeTime(slots.zeroSlot),
			slotLength: safeTime(slots.slotLength),
		},
	});

	lucid.selectWallet.fromAddress(options.fundingAddress, options.fundingInputs);

	const builder = await buildPlanTransaction(plan, options, lucid);
	if (
		options.collateralLovelace !== undefined &&
		(options.collateralLovelace <= 0n ||
			options.collateralLovelace > options.authorization.maxCollateralExposure)
	)
		throw new Error("Collateral floor exceeds approved exposure");
	const built = await builder.complete({
		localUPLCEval: true,
		...(options.collateralLovelace !== undefined
			? { setCollateral: options.collateralLovelace }
			: {}),
	});
	const cbor = built.toCBOR();

	withCMLScope((own) => {
		const tx = own(CML.Transaction.from_cbor_hex(cbor));
		const witnesses = own(tx.witness_set());
		const keys = witnesses.vkeywitnesses();

		if (keys && own(keys).len() !== 0)
			throw new Error("Unsigned construction produced key witnesses");
	});

	let finalEvaluation = null;

	if (captured) {
		const measured = await options.evaluator.evaluate({
			...captured,
			tx: cbor,
		});

		finalEvaluation = checkFinalBudgets(cbor, measured, captured.context);
	} else if (plan.inputs.some((i) => i.redeemer !== null) || plan.mint.length) {
		throw new Error("Missing construction evaluation context");
	}

	// Checks all effects, including exact protected outputs, input allowlists and collateral exposure.
	const approval = verifyTransactionEffects(cbor, plan, options.authorization);
	const estimatedSignedBytes =
		cbor.length / 2 + approval.requiredWitnesses.length * 128;
	if (
		estimatedSignedBytes >
		(await options.provider.getProtocolParameters()).maxTxSize
	)
		throw new Error(
			"Transaction exceeds maximum size including key-witness allowance",
		);

	return {
		cbor,
		txId: approval.bodyHash,
		bytes: cbor.length / 2,
		estimatedSignedBytes,
		effects: approval.effects,
		finalEvaluation,
		signed: false as const,
		submitReady: false as const,
		networkVerified: false as const,
		deploymentReady: false as const,
	};
}
