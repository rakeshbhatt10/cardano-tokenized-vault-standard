import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { z } from "zod";
import { validatorToScriptHash, type Provider } from "@lucid-evolution/lucid";
import { loadFactoryProof } from "../factory/proof.ts";
import { decodePoolDatum } from "../staking/datum.ts";
import {
	loadFactoryStakingSnapshot,
	setupFactoryPool,
} from "./factory-pool.ts";

const hash = (bytes: number) =>
	z.string().regex(new RegExp(`^[0-9a-f]{${bytes * 2}}$`));
const index = z
	.string()
	.regex(/^(0|[1-9][0-9]{0,9})$/)
	.refine((v) => BigInt(v) <= 4294967295n);
const asset = z
	.object({
		policyId: hash(28),
		tokenNameHex: z.string().regex(/^(?:[0-9a-f]{2}){0,32}$/),
	})
	.strict();
const manifestSchema = z
	.object({
		schema: z.literal("FRAC-MIXED-OWNER-PREPROD-DEPLOYMENT-1"),
		network: z.literal("Preprod"),
		networkMagic: z.literal(1),
		factoryPolicy: hash(28),
		factoryBuildId: hash(32),
		managerAddress: z.string(),
		poolPolicyId: hash(28),
		poolAddress: z.string(),
		validatorParameters: z
			.object({
				bootstrapRef: z
					.object({ txHash: hash(32), outputIndex: index })
					.strict(),
				manager: hash(28),
				rewardsDistributor: hash(28),
				stakingAsset: asset,
				rewardAsset: asset,
				initiallyLocked: z.literal(false),
				vaultSupported: z.literal(true),
				factoryPolicy: hash(28),
			})
			.strict(),
		referenceScriptRef: z
			.object({
				txHash: hash(32),
				outputIndex: z.number().int().min(0).max(4294967295),
			})
			.strict(),
	})
	.passthrough();
const sha = (bytes: Uint8Array) =>
	createHash("sha256").update(bytes).digest("hex");

/** Import public deployment evidence with fresh NFT/reference resolution. This
 * never initializes another pool, signs, submits or trusts cached pool balances.
 * The caller must independently bind the provider to Preprod genesis. */
export async function importExistingFactoryPool(
	directory: string,
	provider: Pick<Provider, "getUtxosByOutRef" | "getUtxoByUnit">,
) {
	const bytes = await readFile(join(directory, "deployment.json"));
	const saved = manifestSchema.parse(JSON.parse(bytes.toString()));
	const source = loadFactoryStakingSnapshot(undefined, "mixed-owner-v1");
	const factory = loadFactoryProof("staking-vault");
	if (
		sha(await readFile(join(directory, "plutus.json"))) !==
			source.blueprintHash ||
		saved.factoryPolicy !== factory.policy ||
		saved.factoryBuildId !== factory.buildId ||
		saved.validatorParameters.factoryPolicy !== factory.policy
	)
		throw Error("Deployed pool source/factory mismatch");
	const [references, pool] = await Promise.all([
		provider.getUtxosByOutRef([saved.referenceScriptRef]),
		provider.getUtxoByUnit(saved.poolPolicyId + "504f4f4c"),
	]);
	const reference = references[0];
	if (
		references.length !== 1 ||
		!reference?.scriptRef ||
		reference.txHash !== saved.referenceScriptRef.txHash ||
		reference.outputIndex !== saved.referenceScriptRef.outputIndex ||
		validatorToScriptHash(reference.scriptRef) !== saved.poolPolicyId ||
		pool.address !== saved.poolAddress ||
		pool.scriptRef ||
		!pool.datum ||
		pool.assets[saved.poolPolicyId + "504f4f4c"] !== 1n
	)
		throw Error("Deployed pool/reference is missing, spent or substituted");
	const state = decodePoolDatum(pool.datum);
	if (state.isLocked)
		throw Error("Vault pool withdrawals must remain unlocked");
	const prepared = setupFactoryPool({
		...saved.validatorParameters,
		network: "Preprod",
		sourcePool: "custom",
		fundingAddress: saved.managerAddress,
		poolReserveLovelace: String(pool.assets.lovelace),
		referenceReserveLovelace: String(reference.assets.lovelace),
		stakingBuild: "mixed-owner-v1",
		deployedProgram: {
			policy: saved.poolPolicyId,
			blueprintSha256: source.blueprintHash,
			script: { type: "PlutusV3", script: reference.scriptRef.script },
			reference: {
				txHash: reference.txHash,
				outputIndex: String(reference.outputIndex),
			},
		},
	});
	if (
		prepared.policy !== saved.poolPolicyId ||
		prepared.address !== saved.poolAddress
	)
		throw Error("Existing pool identity changed during import");
	return {
		prepared,
		observation: {
			checkedAt: new Date().toISOString(),
			deploymentSha256: sha(bytes),
			poolRef: { txHash: pool.txHash, outputIndex: pool.outputIndex },
			referenceRef: saved.referenceScriptRef,
			poolDatum: pool.datum,
			poolAssets: pool.assets,
			liveIdentityVerified: true,
			networkVerified: false,
			stakingIntegrated: false,
			deploymentReady: false,
		},
	};
}
