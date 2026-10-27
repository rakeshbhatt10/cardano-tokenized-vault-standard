import {
	CML,
	Data,
	coreToTxOutput,
	withCMLScope,
	type Provider,
	type UTxO,
} from "@lucid-evolution/lucid";
export const normalizedUTxO = (u: UTxO) =>
	JSON.stringify({
		ref: u.txHash + "#" + u.outputIndex,
		address: u.address,
		assets: Object.entries(u.assets)
			.sort()
			.map(([k, v]) => [k, String(v)]),
		datum: u.datum ? Data.to(Data.from(u.datum)) : null,
		datumHash: u.datumHash ?? null,
		script: u.scriptRef ?? null,
	});

/** Resolve every normal output and prove previously-live reserved outputs remain unchanged. */
export async function readOperationOutputs(
	provider: Provider,
	cbor: string,
	txId: string,
	preserved: UTxO[],
) {
	const expected = withCMLScope((own) => {
		const body = own(own(CML.Transaction.from_cbor_hex(cbor)).body());
		if (own(CML.hash_transaction(body)).to_hex() !== txId)
			throw Error("Operation signed hash mismatch");
		const outputs = own(body.outputs());
		return Array.from({ length: outputs.len() }, (_, outputIndex) => ({
			...coreToTxOutput(own(outputs.get(outputIndex))),
			txHash: txId,
			outputIndex,
		}));
	});
	const query = (utxos: UTxO[]) =>
		provider.getUtxosByOutRef(
			utxos.map((u) => ({ txHash: u.txHash, outputIndex: u.outputIndex })),
		);
	const [outputs, fresh] = await Promise.all([
		query(expected),
		query(preserved),
	]);
	const equal = (a: UTxO[], b: UTxO[]) =>
		a.length === b.length &&
		a.every((u) => b.some((v) => normalizedUTxO(u) === normalizedUTxO(v)));
	if (!equal(expected, outputs))
		throw Error("Confirmed operation output readback mismatch");
	if (!equal(preserved, fresh))
		throw Error(
			"Protected reference, collateral or other-vault output changed",
		);
	return { outputs, preserved: fresh };
}
