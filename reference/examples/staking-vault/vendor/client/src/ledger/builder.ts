import { ledgerValue } from "@ctvs/cardano";
import type { ComposedPlan as TransactionPlan } from "../planning/model.ts";
import { type Address, encodeData, hex } from "@ctvs/protocol";
import {
	credentialToAddress,
	type LucidEvolution,
	type Network,
	type TxBuilder,
	validatorToScriptHash,
} from "@lucid-evolution/lucid";
import type { UnsignedOptions } from "../unsigned.ts";

const datum = (data: Parameters<typeof encodeData>[0]) => hex(encodeData(data));

function address(value: Address, network: Network) {
	const credential = (c: Address["payment"]) => ({
		type: c.type === "key" ? ("Key" as const) : ("Script" as const),
		hash: c.hash,
	});

	return credentialToAddress(
		network,
		credential(value.payment),
		value.stake === null ? undefined : credential(value.stake),
	);
}

export function safeTime(time: bigint) {
	const value = Number(time);

	if (!Number.isSafeInteger(value))
		throw new Error("Validity exceeds safe conversion range");

	return value;
}

/** Lower one canonical plan without signing, submission or completion side effects. */
export async function buildPlanTransaction(
	plan: TransactionPlan,
	options: UnsignedOptions,
	lucid: LucidEvolution,
) {
	let builder = lucid.newTx();

	if (options.explicitFundingInputs?.length)
		builder = builder.collectFrom(options.explicitFundingInputs);

	builder = attachReference(builder, plan, options);
	if (plan.staking) {
		if (
			!options.stakingScript ||
			validatorToScriptHash(options.stakingScript) !== plan.staking.poolPolicy
		) {
			throw new Error("Staking program binding mismatch");
		}
		if (options.stakingReference) {
			if (
				!options.stakingReference.scriptRef ||
				validatorToScriptHash(options.stakingReference.scriptRef) !==
					plan.staking.poolPolicy
			) {
				throw new Error("Staking reference script mismatch");
			}
			builder = builder.readFrom([options.stakingReference]);
		} else {
			builder = builder.attach.SpendingValidator(options.stakingScript);
			if (plan.mint.some((m) => m.policy === plan.staking!.poolPolicy))
				builder = builder.attach.MintingPolicy(options.stakingScript);
		}
	}

	const resolve = async (ref: { txId: string; index: bigint }) => {
		const found = await options.provider.getUtxosByOutRef([
			{ txHash: ref.txId, outputIndex: Number(ref.index) },
		]);

		if (found.length !== 1 || !found[0])
			throw new Error("Missing or ambiguous resolved input");

		return found[0];
	};

	if (plan.referenceInputs.length)
		builder = builder.readFrom(
			await Promise.all(plan.referenceInputs.map(resolve)),
		);

	for (const input of plan.inputs) {
		const utxo = await resolve(input.ref);

		builder =
			input.redeemer === null
				? builder.collectFrom([utxo])
				: builder.collectFrom([utxo], datum(input.redeemer));
	}

	if (
		!options.vaultReference &&
		plan.inputs.some((i) => i.role === "state" || i.role === "request")
	)
		builder = builder.attach.SpendingValidator(options.vaultScript);

	if (plan.inputs.some((i) => i.role === "claim" || i.role === "request"))
		throw new Error("Asynchronous input in CTVS-1 plan");

	if (!options.vaultReference && plan.mint.length)
		builder = builder.attach.MintingPolicy(options.vaultScript);

	for (const mint of plan.mint)
		builder = builder.mintAssets(
			Object.fromEntries(
				Object.entries(mint.assets).map(([name, quantity]) => [
					mint.policy + name,
					quantity,
				]),
			),
			datum(mint.redeemer),
		);

	builder = payOutputs(builder, plan, options.network);

	for (const signer of plan.requiredSigners)
		builder = builder.addSignerKey(signer);

	if (plan.validity)
		builder = builder
			.validFrom(safeTime(plan.validity.lowerPosixMs))
			.validTo(safeTime(plan.validity.upperPosixMs));

	return builder;
}

function attachReference(
	builder: TxBuilder,
	plan: TransactionPlan,
	options: UnsignedOptions,
) {
	const needsVault =
		plan.mint.length > 0 ||
		plan.inputs.some((i) => i.role === "state" || i.role === "request");

	if (options.vaultReference && needsVault) {
		if (
			!options.vaultReference.scriptRef ||
			validatorToScriptHash(options.vaultReference.scriptRef) !==
				plan.implementation.policy
		)
			throw new Error("Vault reference script mismatch");

		builder = builder.readFrom([options.vaultReference]);
	}

	return builder;
}

function payOutputs(
	builder: TxBuilder,
	plan: TransactionPlan,
	network: Network,
) {
	for (const output of plan.outputs) {
		const to = address(output.address, network);

		builder =
			output.datum === null
				? builder.pay.ToAddress(to, ledgerValue(output.value))
				: builder.pay.ToAddressWithData(
						to,
						{ kind: "inline", value: datum(output.datum) },
						ledgerValue(output.value),
					);
	}

	return builder;
}
