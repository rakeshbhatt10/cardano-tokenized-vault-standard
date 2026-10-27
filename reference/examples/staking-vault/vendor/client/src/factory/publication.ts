import { applyParamsToScript } from "../../support/application.ts";
import { createHash } from "node:crypto";
import { z } from "zod";
import { protocolRef, protocolValue } from "@ctvs/cardano";
import { refId, type OutRef } from "@ctvs/protocol";
import {
	Blockfrost,
	CML,
	Data,
	Lucid,
	SLOT_CONFIG_NETWORK,
	
	coreToTxOutput,
	getAddressDetails,
	validatorToAddress,
	validatorToScriptHash,
	withCMLScope,
	type Provider,
	type UTxO,
} from "@lucid-evolution/lucid";
import {
	verifyTransactionEffects,
	type WalletAuthorization,
} from "../ledger/effects/effects.ts";
import { blake, loadFactoryProof } from "./proof.ts";

const hash = (bytes: Uint8Array) =>
	createHash("sha256").update(bytes).digest("hex");
const q = z
	.string()
	.regex(/^[1-9][0-9]{0,18}$/)
	.refine((v) => BigInt(v) <= (1n << 63n) - 1n);
const outRef = z
	.object({
		txId: z.string().regex(/^[0-9a-f]{64}$/),
		index: z
			.string()
			.regex(/^(0|[1-9][0-9]{0,9})$/)
			.refine((v) => BigInt(v) <= 4294967295n),
	})
	.strict();
const schema = z
	.object({
		schema: z.literal("STAKING-CTVS1-FACTORY-PUBLICATION-SETTINGS-1"),
		network: z.enum(["Mainnet", "Preprod", "Preview"]),
		fundingAddress: z.string(),
		reserves: z.object({ factory: q, prefix0: q, prefix1: q }).strict(),
		maxNetworkFeeLovelace: q,
		protectedInputs: z.array(outRef),
	})
	.strict();
export type FactoryPublicationSettings = z.infer<typeof schema>;
export type FactoryPublicationStage = "factory" | "prefix0" | "prefix1";
export const FACTORY_PUBLICATION_STAGES = [
	"factory",
	"prefix0",
	"prefix1",
] as const;

export function readFactoryPublicationSettings(
	input: unknown,
): FactoryPublicationSettings {
	const settings = schema.parse(input);
	const address = getAddressDetails(settings.fundingAddress);
	if (
		address.networkId !== (settings.network === "Mainnet" ? 1 : 0) ||
		address.paymentCredential?.type !== "Key"
	)
		throw Error(
			"Funding must be an explicit key address on the selected network",
		);
	const protectedRefs = settings.protectedInputs.map(
		(r) => r.txId + "#" + r.index,
	);
	if (new Set(protectedRefs).size !== protectedRefs.length)
		throw Error("Duplicate protected input");
	return settings;
}

/** Factory deployment means publishing reusable code/data; there is no factory initialization mint. */
export function prepareFactoryPublication(input: unknown) {
	const settings = readFactoryPublicationSettings(input);
	const source = loadFactoryProof("staking-vault");
	const controllerBytes = source.controllerTemplate.length / 2;
	const appliedExampleBytes =
		applyParamsToScript(source.controllerTemplate, ["00".repeat(32)]).length /
		2;
	return {
		schema: "STAKING-CTVS1-FACTORY-PUBLICATION-1" as const,
		settings,
		buildId: source.buildId,
		factoryPolicy: source.policy,
		factoryScript: source.script,
		configLock: source.lock,
		configLockAddress: validatorToAddress(settings.network, source.lock),
		prefixHash: blake(source.prefix),
		prefixSha256: hash(source.prefix),
		parts: source.parts,
		implementation: "CTVS1-MIXED-FACTORY-1" as const,
		compiler: source.manifest.compiler as string,
		sourceHashes: source.sourceHashes,
		sourceSelectionSha256: source.sourceSelectionSha256,
		publicationStages: FACTORY_PUBLICATION_STAGES,
		controllerTemplateBytes: controllerBytes,
		controllerAppliedExampleBytes: appliedExampleBytes,
		controllerPublicationFixtureLimit: 16384,
		controllerPublicationBlocked: appliedExampleBytes + 128 > 16384,
		factoryPolicyChangesWithTemplate: true as const,
		registrationIssued: false as const,
		stakingIntegrated: false as const,
		deploymentReady: false as const,
		executionEnabled: false as const,
	};
}
export type PreparedFactoryPublication = ReturnType<
	typeof prepareFactoryPublication
>;

export function verifyFactoryPublicationPreparation(
	prepared: PreparedFactoryPublication,
) {
	const current = prepareFactoryPublication(prepared.settings);
	const json = (v: unknown) => JSON.stringify(v);
	if (json(current) !== json(prepared))
		throw Error("Stale or altered factory publication preparation");
	return current;
}

function publicationOutput(
	prepared: PreparedFactoryPublication,
	stage: FactoryPublicationStage,
) {
	if (!FACTORY_PUBLICATION_STAGES.includes(stage))
		throw Error("Unknown factory publication stage");
	return {
		address: prepared.settings.fundingAddress,
		lovelace: BigInt(prepared.settings.reserves[stage]),
		datum:
			stage === "factory"
				? undefined
				: Data.to(prepared.parts[stage === "prefix0" ? 0 : 1]!),
		script: stage === "factory" ? prepared.factoryScript : undefined,
	};
}

/** Re-query explicit clean funding. Never consume protected seeds, reference scripts or datum-bearing outputs. */
export async function constructFactoryPublication(
	prepared: PreparedFactoryPublication,
	stage: FactoryPublicationStage,
	provider: Provider,
	fundingSnapshot?: readonly UTxO[],
) {
	const current = verifyFactoryPublicationPreparation(prepared);
	const output = publicationOutput(current, stage);
	const excluded = new Set(
		current.settings.protectedInputs.map((r) => r.txId + "#" + r.index),
	);
	const offered =
		fundingSnapshot ??
		(await provider.getUtxos(current.settings.fundingAddress));
	const candidates = offered.filter(
		(u) =>
			!u.scriptRef &&
			!u.datum &&
			!u.datumHash &&
			!excluded.has(refId(protocolRef(u))),
	);
	if (
		!candidates.length ||
		candidates.some((u) => u.address !== current.settings.fundingAddress)
	)
		throw Error(
			"Explicit clean funding at the configured key address is required",
		);
	const resolved = await provider.getUtxosByOutRef(
		candidates.map((u) => ({ txHash: u.txHash, outputIndex: u.outputIndex })),
	);
	const normalized = (u: UTxO) =>
		JSON.stringify(
			{
				ref: protocolRef(u),
				address: u.address,
				datum: u.datum ?? null,
				datumHash: u.datumHash ?? null,
				scriptRef: u.scriptRef ?? null,
				assets: Object.fromEntries(Object.entries(u.assets).sort()),
			},
			(_, v) => (typeof v === "bigint" ? v.toString() : v),
		);
	if (
		resolved.length !== candidates.length ||
		new Set(candidates.map((u) => refId(protocolRef(u)))).size !==
			candidates.length ||
		candidates.some(
			(u) => !resolved.some((r) => normalized(r) === normalized(u)),
		)
	)
		throw Error("Funding snapshot changed, duplicated or spent");
	const guarded = new Proxy(provider, {
		get(target, key) {
			if (key === "submitTx")
				return () => {
					throw Error("Factory publication submission disabled");
				};
			const value = Reflect.get(target, key);
			return typeof value === "function" ? value.bind(target) : value;
		},
	});
	const lucid = await Lucid(guarded, current.settings.network);
	lucid.selectWallet.fromAddress(current.settings.fundingAddress, candidates);
	const built = await lucid
		.newTx()
		.pay.ToAddressWithData(
			output.address,
			output.datum ? { kind: "inline", value: output.datum } : undefined,
			{ lovelace: output.lovelace },
			output.script,
		)
		.complete();
	const cbor = built.toCBOR();
	const slots =
		lucid.config().slotConfig ?? SLOT_CONFIG_NETWORK[current.settings.network];
	const auth: WalletAuthorization = {
		networkId: current.settings.network === "Mainnet" ? 1 : 0,
		networkName: current.settings.network,
		networkDomain: "factory-publication:" + current.settings.network,
		planInputs: [],
		allowedFundingInputs: candidates.map((u) => ({
			ref: protocolRef(u),
			address: u.address,
			value: protocolValue(u.assets),
			referenceScript: null,
		})),
		allowedCollateralInputs: [],
		allowedReferenceInputs: [],
		change: {
			address: current.settings.fundingAddress,
			datum: { kind: "none" },
		},
		maxNetworkFee: BigInt(current.settings.maxNetworkFeeLovelace),
		maxCollateralExposure: 0n,
		permittedExtraOutputs: [
			{
				address: output.address,
				value: { ada: output.lovelace },
				datum: output.datum
					? { kind: "inline", cbor: output.datum }
					: { kind: "none" },
				referenceScript: output.script ?? null,
			},
		],
		additionalRequiredSigners: [],
		validitySlots: { lower: null, upper: null },
		slotConfig: {
			zeroTime: BigInt(slots.zeroTime),
			zeroSlot: BigInt(slots.zeroSlot),
			slotLength: BigInt(slots.slotLength),
		},
	};
	const approval = verifyTransactionEffects(cbor, null, auth);
	const params = await provider.getProtocolParameters();
	const estimatedSignedBytes =
		cbor.length / 2 + approval.requiredWitnesses.length * 128;
	if (estimatedSignedBytes > params.maxTxSize)
		throw Error(
			"Factory publication exceeds ledger size including witness allowance",
		);
	const inspected = withCMLScope((own) => {
		const tx = own(CML.Transaction.from_cbor_hex(cbor));
		const keys = own(tx.witness_set()).vkeywitnesses();
		if (keys && own(keys).len())
			throw Error("Unexpected factory publication key witnesses");
		const body = own(tx.body()),
			outputs = own(body.outputs());
		const rows: UTxO[] = [];
		for (let i = 0; i < outputs.len(); i++) {
			const raw = own(outputs.get(i));
			if (
				(coreToTxOutput(raw).assets.lovelace ?? 0n) <
				CML.min_ada_required(raw, params.coinsPerUtxoByte)
			)
				throw Error("Factory publication output below minimum ADA");
			rows.push({
				...coreToTxOutput(raw),
				txHash: approval.bodyHash,
				outputIndex: i,
			});
		}
		return { feeLovelace: body.fee().toString(), outputs: rows };
	});
	const matches = inspected.outputs.filter(
		(u) =>
			u.address === output.address &&
			u.assets.lovelace === output.lovelace &&
			(stage === "factory"
				? u.scriptRef?.script === current.factoryScript.script
				: u.datum === output.datum),
	);
	if (matches.length !== 1)
		throw Error("Factory publication output is ambiguous");
	return {
		schema: "STAKING-CTVS1-FACTORY-PUBLICATION-UNSIGNED-1" as const,
		stage,
		cbor,
		txId: approval.bodyHash,
		bytes: cbor.length / 2,
		estimatedSignedBytes,
		feeLovelace: inspected.feeLovelace,
		expectedReference: protocolRef(matches[0]!),
		referenceAcceptedOnLedger: false as const,
		effects: approval.effects,
		// In-memory approval for the separate explicit Preprod signing boundary.
		signingApproval: approval,
		keyWitnesses: 0,
		scriptPurposes: [] as string[],
		signed: false as const,
		submitted: false as const,
		deploymentReady: false as const,
		executionEnabled: false as const,
	};
}

/** Verify one current ledger reference; used to gate sequential publication. */
export async function verifyFactoryPublicationReference(
	prepared: PreparedFactoryPublication,
	stage: FactoryPublicationStage,
	ref: OutRef,
	provider: Pick<Provider, "getUtxosByOutRef">,
) {
	const current = verifyFactoryPublicationPreparation(prepared);
	outRef.parse({ txId: ref.txId, index: ref.index.toString() });
	const values = await provider.getUtxosByOutRef([
		{ txHash: ref.txId, outputIndex: Number(ref.index) },
	]);
	const u = values[0],
		expected = publicationOutput(current, stage);
	if (
		values.length !== 1 ||
		!u ||
		refId(protocolRef(u)) !== refId(ref) ||
		u.address !== expected.address ||
		Object.keys(u.assets).join() !== "lovelace" ||
		u.assets.lovelace !== expected.lovelace ||
		(stage === "factory"
			? u.datum ||
				u.datumHash ||
				!u.scriptRef ||
				u.scriptRef.type !== "PlutusV3" ||
				u.scriptRef.script !== current.factoryScript.script ||
				validatorToScriptHash(u.scriptRef) !== current.factoryPolicy
			: u.scriptRef ||
				!u.datum ||
				Data.to(Data.from(u.datum)) !== expected.datum)
	)
		throw Error(
			"Factory publication reference is missing, substituted or changed: " +
				stage,
		);
	return {
		stage,
		ref,
		address: u.address,
		lovelace: u.assets.lovelace.toString(),
	};
}

/** Explicit accepted references only; predicted unsigned transaction IDs are not accepted-chain evidence. */
export async function verifyFactoryPublicationReferences(
	prepared: PreparedFactoryPublication,
	references: Record<FactoryPublicationStage, OutRef>,
	provider: Pick<Provider, "getUtxosByOutRef">,
) {
	const current = verifyFactoryPublicationPreparation(prepared);
	if (
		Object.keys(references).sort().join() !==
			[...FACTORY_PUBLICATION_STAGES].sort().join() ||
		new Set(Object.values(references).map(refId)).size !== 3
	)
		throw Error(
			"Three distinct accepted factory publication references are required",
		);
	const result = await Promise.all(
		FACTORY_PUBLICATION_STAGES.map((stage) =>
			verifyFactoryPublicationReference(
				current,
				stage,
				references[stage],
				provider,
			),
		),
	);
	return {
		schema: "STAKING-CTVS1-FACTORY-PUBLICATION-READBACK-1" as const,
		factoryPolicy: current.factoryPolicy,
		buildId: current.buildId,
		references: result,
		publicationVerified: true as const,
		registrationIssued: false as const,
		stakingIntegrated: false as const,
		deploymentReady: false as const,
		executionEnabled: false as const,
	};
}

export function readFactoryPublicationReferences(
	input: unknown,
): Record<FactoryPublicationStage, OutRef> {
	const refs = z
		.object({ factory: outRef, prefix0: outRef, prefix1: outRef })
		.strict()
		.parse(input);
	return Object.fromEntries(
		FACTORY_PUBLICATION_STAGES.map((stage) => [
			stage,
			{ txId: refs[stage].txId, index: BigInt(refs[stage].index) },
		]),
	) as Record<FactoryPublicationStage, OutRef>;
}

/** Fixed endpoints and explicit network identity; no signer or submission capability is returned. */
export async function loadFactoryPublicationContext(
	prepared: PreparedFactoryPublication,
	apiKey: string,
) {
	const current = verifyFactoryPublicationPreparation(prepared);
	const network = current.settings.network,
		prefix = network.toLowerCase();
	if (!apiKey || !apiKey.startsWith(prefix))
		throw Error(
			"Blockfrost project key must match the explicit publication network",
		);
	const url = `https://cardano-${prefix}.blockfrost.io/api/v0`;
	const read = async (path: string) => {
		const r = await fetch(url + path, {
			headers: { project_id: apiKey },
			signal: AbortSignal.timeout(20000),
		});
		if (!r.ok)
			throw Error(
				"Factory publication provider read failed (" + r.status + ")",
			);
		return r.json();
	};
	const genesis = await read("/genesis");
	if (
		genesis.network_magic !==
		{ Mainnet: 764824073, Preprod: 1, Preview: 2 }[network]
	)
		throw Error("Publication provider network magic mismatch");
	const tip = await read("/blocks/latest");
	if (!Number.isSafeInteger(tip.slot) || !/^[0-9a-f]{64}$/.test(tip.hash))
		throw Error("Malformed publication chain point");
	const transport = new Blockfrost(url, apiKey);
	const provider = new Proxy(transport, {
		get(target, key) {
			if (key === "submitTx")
				return () => {
					throw Error("Factory publication submission disabled");
				};
			const v = Reflect.get(target, key);
			return typeof v === "function" ? v.bind(target) : v;
		},
	});
	return {
		provider,
		observation: {
			network,
			networkMagic: genesis.network_magic,
			slot: tip.slot,
			blockHash: tip.hash,
			checkedAt: new Date().toISOString(),
			source:
				"Blockfrost read-only observation; not independent consensus verification",
		},
	};
}
