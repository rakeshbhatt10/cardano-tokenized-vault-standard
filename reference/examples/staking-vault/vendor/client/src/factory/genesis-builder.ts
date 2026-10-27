import {
	Constr,
	Data,
	getAddressDetails,
	validatorToAddress,
	validatorToScriptHash,
	type LucidEvolution,
	type UTxO,
} from "@lucid-evolution/lucid";
import { factoryOperationContext } from "./deployment.ts";
import type { prepareFactoryVault } from "./vault.ts";

export interface FactoryGenesisReferences {
	factory: UTxO;
	prefix0: UTxO;
	prefix1: UTxO;
	controller: UTxO;
}

/** Assemble one empty vault + registration mint. The caller must freshly resolve
 * every input/reference, complete/evaluate, inspect all effects and archive the
 * body before signing. This function never completes, signs or submits a tx. */
export function buildFactoryVaultGenesis(
	lucid: LucidEvolution,
	candidate: ReturnType<typeof prepareFactoryVault>,
	seed: UTxO,
	references: FactoryGenesisReferences,
	certificateReserve: bigint,
) {
	factoryOperationContext(candidate); // Re-derive all immutable commitments.
	const id = (u: UTxO) => u.txHash + "#" + u.outputIndex;
	const refs = Object.values(references);
	const expectedSeed =
		candidate.input.seed.txId + "#" + candidate.input.seed.index;
	const positionSeed = candidate.input.poolBinding.positionSeed;
	if (
		lucid.config().network !== candidate.input.network ||
		id(seed) !== expectedSeed ||
		expectedSeed === positionSeed.txId + "#" + positionSeed.index ||
		seed.scriptRef ||
		seed.datum ||
		seed.datumHash ||
		Object.keys(seed.assets).some((unit) => unit !== "lovelace") ||
		getAddressDetails(seed.address).paymentCredential?.type !== "Key" ||
		certificateReserve <= 0n ||
		certificateReserve > (1n << 63n) - 1n ||
		new Set([id(seed), ...refs.map(id)]).size !== 5 ||
		refs.some((u) => id(u) === positionSeed.txId + "#" + positionSeed.index) ||
		!references.factory.scriptRef ||
		validatorToScriptHash(references.factory.scriptRef) !==
			candidate.source.policy ||
		references.factory.scriptRef.script !== candidate.source.script.script ||
		!references.controller.scriptRef ||
		validatorToScriptHash(references.controller.scriptRef) !==
			candidate.controller ||
		references.controller.scriptRef.script !== candidate.script.script ||
		references.prefix0.scriptRef ||
		references.prefix1.scriptRef ||
		references.prefix0.datum !== Data.to(candidate.source.parts[0]!) ||
		references.prefix1.datum !== Data.to(candidate.source.parts[1]!)
	)
		throw Error("Factory genesis seed/reference/reserve binding mismatch");
	const outRef = (u: UTxO) => new Constr(0, [u.txHash, BigInt(u.outputIndex)]);
	const lockAddress = validatorToAddress(
		candidate.input.network,
		candidate.source.lock,
	);
	return lucid
		.newTx()
		.readFrom(refs)
		.collectFrom([seed])
		.mintAssets(
			{ [candidate.configUnit]: 1n, [candidate.stateUnit]: 1n },
			Data.to(new Constr(3, ["43545653", 2n, new Constr(0, [0n, 1n])])),
		)
		.mintAssets(
			{ [candidate.certificateUnit]: 1n },
			Data.to(
				new Constr(0, [
					candidate.instance,
					outRef(references.prefix0),
					outRef(references.prefix1),
					0n,
					1n,
					2n,
				]),
			),
		)
		.pay.ToAddressWithData(
			lockAddress,
			{ kind: "inline", value: Data.to(candidate.configData) },
			{ lovelace: candidate.input.configReserve, [candidate.configUnit]: 1n },
		)
		.pay.ToAddressWithData(
			candidate.address,
			{ kind: "inline", value: Data.to(candidate.stateData) },
			{ lovelace: candidate.input.stateReserve, [candidate.stateUnit]: 1n },
		)
		.pay.ToAddressWithData(
			lockAddress,
			{ kind: "inline", value: Data.to(candidate.registration) },
			{ lovelace: certificateReserve, [candidate.certificateUnit]: 1n },
		);
}
