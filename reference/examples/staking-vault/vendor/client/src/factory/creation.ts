import {
	CML,
	Lucid,
	SLOT_CONFIG_NETWORK,
	withCMLScope,
	type Provider,
	type UTxO,
} from "@lucid-evolution/lucid";
import { protocolRef, protocolValue } from "@ctvs/cardano";
import { refId, type OutRef } from "@ctvs/protocol";
import { constructUnsigned } from "../unsigned.ts";
import {
	verifyTransactionEffects,
	type WalletAuthorization,
} from "../ledger/effects/effects.ts";
import { RecordedEvaluator } from "../../../../../../testing/ledger/evaluator.ts";
import { factoryOperationContext } from "./deployment.ts";
import { factoryGenesisPlan } from "./genesis-plan.ts";
import type { FactoryGenesisReferences } from "./genesis-builder.ts";
import type { prepareFactoryVault } from "./vault.ts";

export interface FactoryCreationLedger {
	provider: Provider;
	fundingAddress: string;
	funding: UTxO[];
	collateral: UTxO[];
	protectedInputs: OutRef[];
	maxNetworkFee: bigint;
	maxCollateralExposure: bigint;
}
const evidence = (u: UTxO) => ({
	ref: protocolRef(u),
	address: u.address,
	value: protocolValue(u.assets),
	referenceScript: u.scriptRef ?? null,
});
const clean = (u: UTxO) =>
	!u.datum &&
	!u.datumHash &&
	!u.scriptRef &&
	Object.keys(u.assets).every((k) => k === "lovelace");

async function checkedLedger(
	vault: ReturnType<typeof prepareFactoryVault>,
	ledger: FactoryCreationLedger,
	genesis: boolean,
) {
	factoryOperationContext(vault);
	const protectedRefs = new Set(
		[
			...ledger.protectedInputs,
			vault.input.poolBinding.positionSeed,
			...(genesis ? [] : [vault.input.seed]),
		].map(refId),
	);
	const all = [...ledger.funding, ...ledger.collateral];
	if (
		!ledger.funding.length ||
		new Set(all.map((u) => refId(protocolRef(u)))).size !== all.length ||
		all.some(
			(u) =>
				!clean(u) ||
				u.address !== ledger.fundingAddress ||
				protectedRefs.has(refId(protocolRef(u))),
		)
	)
		throw Error(
			"Creation funding/collateral includes protected, duplicate or non-funding inputs",
		);
	const current = await ledger.provider.getUtxosByOutRef(
		all.map((u) => ({ txHash: u.txHash, outputIndex: u.outputIndex })),
	);
	const same = (u: UTxO) =>
		JSON.stringify(evidence(u), (_, v) =>
			typeof v === "bigint" ? String(v) : v,
		);
	if (
		current.length !== all.length ||
		all.some((u) => !current.some((c) => same(c) === same(u)))
	)
		throw Error("Creation funding snapshot changed");
	return ledger;
}

function authorization(
	vault: ReturnType<typeof prepareFactoryVault>,
	ledger: FactoryCreationLedger,
): WalletAuthorization {
	const slots = SLOT_CONFIG_NETWORK[vault.input.network];
	return {
		networkId: 0,
		networkName: vault.input.network,
		networkDomain: vault.input.terms.networkDomain,
		planInputs: [],
		allowedFundingInputs: ledger.funding.map(evidence),
		allowedCollateralInputs: ledger.collateral.map(evidence),
		allowedReferenceInputs: [],
		change: { address: ledger.fundingAddress, datum: { kind: "none" } },
		maxNetworkFee: ledger.maxNetworkFee,
		maxCollateralExposure: ledger.maxCollateralExposure,
		permittedExtraOutputs: [],
		additionalRequiredSigners: [],
		validitySlots: { lower: null, upper: null },
		slotConfig: {
			zeroTime: BigInt(slots.zeroTime),
			zeroSlot: BigInt(slots.zeroSlot),
			slotLength: BigInt(slots.slotLength),
		},
	};
}

async function inspectMinimumAda(cbor: string, provider: Provider) {
	const params = await provider.getProtocolParameters();
	return withCMLScope((own) => {
		const tx = own(CML.Transaction.from_cbor_hex(cbor)),
			outputs = own(own(tx.body()).outputs());
		const reserves = [];
		for (let i = 0; i < outputs.len(); i++) {
			const output = own(outputs.get(i)),
				actual = own(output.amount()).coin(),
				minimum = CML.min_ada_required(output, params.coinsPerUtxoByte);
			if (actual < minimum)
				throw Error("Creation output below ledger minimum ADA");
			reserves.push({
				index: i,
				actualLovelace: String(actual),
				minimumLovelace: String(minimum),
			});
		}
		return reserves;
	});
}

/** Publish only this controller, retaining both its genesis and position seeds. */
export async function constructFactoryVaultPublication(
	vault: ReturnType<typeof prepareFactoryVault>,
	reserve: bigint,
	ledger: FactoryCreationLedger,
) {
	await checkedLedger(vault, ledger, false);
	const guarded = new Proxy(ledger.provider, {
		get(target, key) {
			if (key === "submitTx")
				return () => {
					throw Error("Unsigned publication cannot submit");
				};
			const value = Reflect.get(target, key);
			return typeof value === "function" ? value.bind(target) : value;
		},
	});
	const lucid = await Lucid(guarded, vault.input.network);
	lucid.selectWallet.fromAddress(ledger.fundingAddress, ledger.funding);
	const built = await lucid
		.newTx()
		.pay.ToAddressWithData(
			ledger.fundingAddress,
			undefined,
			{ lovelace: reserve },
			vault.script,
		)
		.complete();
	const cbor = built.toCBOR(),
		auth = authorization(vault, ledger);
	auth.allowedCollateralInputs = [];
	auth.permittedExtraOutputs = [
		{
			address: ledger.fundingAddress,
			value: { ada: reserve },
			datum: { kind: "none" },
			referenceScript: vault.script,
		},
	];
	const approval = verifyTransactionEffects(cbor, null, auth);
	const estimatedSignedBytes =
		cbor.length / 2 + approval.requiredWitnesses.length * 128;
	if (
		estimatedSignedBytes >
		(await ledger.provider.getProtocolParameters()).maxTxSize
	)
		throw Error("Controller publication exceeds signed-size allowance");
	return {
		cbor,
		txId: built.toHash(),
		bytes: cbor.length / 2,
		estimatedSignedBytes,
		feeLovelace: String(approval.fee),
		minimumAda: await inspectMinimumAda(cbor, ledger.provider),
		effects: approval.effects,
		approval,
		signed: false,
		submitted: false,
	};
}

/** Complete/evaluate both mint purposes, then verify all effects against a separate intent. */
export async function constructFactoryVaultGenesis(
	vault: ReturnType<typeof prepareFactoryVault>,
	seed: UTxO,
	refs: FactoryGenesisReferences,
	certificateReserve: bigint,
	ledger: FactoryCreationLedger,
) {
	await checkedLedger(vault, ledger, true);
	if (!ledger.collateral.length)
		throw Error("Explicit creation collateral required");
	const plan = factoryGenesisPlan(vault, refs, certificateReserve),
		auth = authorization(vault, ledger);
	const actualRefs = await ledger.provider.getUtxosByOutRef(
		Object.values(refs).map((u) => ({
			txHash: u.txHash,
			outputIndex: u.outputIndex,
		})),
	);
	if (
		actualRefs.length !== 4 ||
		Object.values(refs).some(
			(u) =>
				!actualRefs.some(
					(a) =>
						a.txHash === u.txHash &&
						a.outputIndex === u.outputIndex &&
						a.scriptRef?.script === u.scriptRef?.script &&
						a.datum === u.datum,
				),
		)
	)
		throw Error("Genesis references changed");
	auth.planInputs = [evidence(seed)];
	auth.allowedFundingInputs = ledger.funding
		.filter((u) => refId(protocolRef(u)) !== refId(protocolRef(seed)))
		.map(evidence);
	auth.allowedReferenceInputs = Object.values(refs).map(evidence);
	const percentage = BigInt(
		(await ledger.provider.getProtocolParameters()).collateralPercentage,
	);
	let collateralFloor = 1n;
	// The SDK estimates collateral before its final fee. Rebuild the unsigned body
	// if necessary, and never return an artifact below the live phase-one minimum.
	for (let attempt = 0; attempt < 3; attempt++) {
		const result = await constructUnsigned(plan, {
			provider: ledger.provider,
			network: vault.input.network,
			fundingAddress: ledger.fundingAddress,
			fundingInputs: ledger.collateral,
			explicitFundingInputs: ledger.funding.filter(
				(u) => refId(protocolRef(u)) !== refId(protocolRef(seed)),
			),
			// Let the SDK apply the live collateral percentage to the actual fee.
			// A 1-lovelace floor avoids its unrelated default 5-ADA floor; review still
			// bounds actual exposure and restricts collateral to the dedicated inputs.
			collateralLovelace: collateralFloor,
			vaultScript: vault.script,
			vaultReference: refs.controller,
			authorization: auth,
			evaluator: new RecordedEvaluator(),
		});
		if (
			!result.finalEvaluation ||
			result.effects.redeemers.length !== 2 ||
			result.effects.redeemers.some((r) => r.purpose !== "mint")
		)
			throw Error("Both genesis mint evaluations are required");
		const approval = verifyTransactionEffects(result.cbor, plan, auth);
		const required = (approval.fee * percentage + 99n) / 100n;
		if (approval.collateralExposure < required) {
			collateralFloor = required;
			if (collateralFloor > ledger.maxCollateralExposure)
				throw Error("Required collateral exceeds approved exposure");
			continue;
		}
		return {
			...result,
			plan,
			approval,
			feeLovelace: String(approval.fee),
			collateralCheck: {
				percentage: String(percentage),
				requiredLovelace: String(required),
				exposureLovelace: String(approval.collateralExposure),
			},
			minimumAda: await inspectMinimumAda(result.cbor, ledger.provider),
		};
	}
	throw Error("Genesis collateral/fee did not converge");
}
