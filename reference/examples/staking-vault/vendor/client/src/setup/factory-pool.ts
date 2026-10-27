import { applyParamsToScript } from "../../support/application.ts";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
	
	Constr,
	validatorToAddress,
	validatorToScriptHash,
	type Script,
} from "@lucid-evolution/lucid";
import { factoryTrustParameter } from "../../protocol/shared-v1/authorization.ts";
import { readPoolSettings } from "./settings.ts";
import type { PoolSettings } from "./settings.ts";
type StakingPoolSettings = PoolSettings & { initiallyLocked:false; vaultSupported:true };
import { encodePoolDatum } from "../staking/datum.ts";
import {
	selectExistingPoolProgram,
	type ExistingPoolProgram,
} from "./existing-pool-program.ts";

export type FactoryPoolSettings = StakingPoolSettings & {
	factoryPolicy: string;
	stakingBuild: "mixed-owner-v1";
	/** Original applied bytes of an existing pool; never re-encode for ledger use. */
	deployedProgram?: ExistingPoolProgram;
};
const root = fileURLToPath(
	new URL("../../../../onchain/staking/", import.meta.url),
);
const sha = (b: Uint8Array) => createHash("sha256").update(b).digest("hex");
export const STAKING_SNAPSHOT_SHA256 =
	"2254e739d1ea424cad7d1b06a05a2b15f9251dbcd6b41fb3132bbd31a889b517";

/** Current staking source snapshot; unsupported builds fail explicitly. */
export function loadFactoryStakingSnapshot(
	directory?: string,
	profile: "mixed-owner-v1" = "mixed-owner-v1",
) {
	if (profile !== "mixed-owner-v1") throw Error("Unsupported staking build profile");
	directory ??= root;
	const bytes = readFileSync(join(directory, "snapshot.json"));
	if (sha(bytes) !== STAKING_SNAPSHOT_SHA256) throw Error("Unrecognized factory staking snapshot");
	const manifest = JSON.parse(bytes.toString());
	if (
		manifest.schema !== "STAKING-EXAMPLE-SOURCE-SNAPSHOT-1" ||
		manifest.compiler !== "aiken v1.1.23+unknown" ||
		manifest.summary.failed !== 0 ||
		manifest.compiledSourceVerified !== true
	)
		throw Error("Invalid factory staking source attestation");
	const inventory = (folder: string, prefix = ""): string[] =>
		readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
			if (entry.isSymbolicLink()) throw Error("Snapshot symlink rejected");
			const path = join(prefix, entry.name);
			return entry.isDirectory()
				? inventory(join(folder, entry.name), path)
				: [path];
		});
	if (
		JSON.stringify(inventory(directory).sort()) !==
		JSON.stringify([...Object.keys(manifest.files), "snapshot.json"].sort())
	)
		throw Error("Factory staking snapshot inventory changed");
	for (const [name, hash] of Object.entries(manifest.files)) {
		if (
			name.startsWith("/") ||
			name.split("/").includes("..") ||
			sha(readFileSync(join(directory, name))) !== hash
		)
			throw Error("Altered factory staking snapshot: " + name);
	}
	const exampleRoot = fileURLToPath(new URL("../../../../", import.meta.url));
	if (manifest.originSnapshotSha256 !== "52c966c171f82f16f83bf4bbee12570e01ebb6c74d5868be96658dd308fceeb2") throw Error("Unrecognized staking import origin");
	for (const [name, digest] of Object.entries(manifest.exampleFiles)) {
		if (name.startsWith("/") || name.split("/").includes("..") || !(name.startsWith("docs/") || name.startsWith("evidence/staking/")) || sha(readFileSync(join(exampleRoot, name))) !== digest) throw Error("Altered staking documentation binding: " + name);
	}
	const blueprintPath = join(exampleRoot, "evidence/staking/blueprint.json");
	const bp = JSON.parse(readFileSync(blueprintPath, "utf8"));
	if (bp.preamble.plutusVersion !== "v3")
		throw Error("Expected Plutus V3 staking build");
	const names = [
		"bootstrap_ref",
		"manager",
		"rewards_distributor",
		"staking_asset",
		"reward_asset",
		"initially_locked",
		"vault_supported",
		"factory_policy",
	];
	const template = (purpose: string) => {
		const values = bp.validators.filter(
			(v: { title: string }) =>
				v.title === "single_staking.single_staking." + purpose,
		);
		if (
			values.length !== 1 ||
			JSON.stringify(
				values[0].parameters.map((p: { title: string }) => p.title),
			) !== JSON.stringify(names) ||
			!/^(?:[0-9a-f]{2})+$/.test(values[0].compiledCode)
		)
			throw Error("Factory staking template/parameter mismatch");
		return values[0].compiledCode as string;
	};
	const program = template("spend");
	if (template("mint") !== program)
		throw Error("Factory pool mint/spend mismatch");
	return {
		manifest,
		template: program,
		blueprintHash: manifest.exampleFiles["evidence/staking/blueprint.json"] as string,
		blueprintPath,
		snapshotPath: directory,
		buildId: "factory-staking:" + profile + ":" + sha(bytes),
	};
}

/** Public testnet preparation only. Factory policy is explicit and does not imply live vault support. */
export function setupFactoryPool(input: FactoryPoolSettings) {
	const {
		factoryPolicy,
		initiallyLocked,
		vaultSupported,
		stakingBuild,
		deployedProgram,
		...base
	} = input;
	if (stakingBuild !== "mixed-owner-v1")
		throw Error("Unsupported staking build profile");
	if (
		initiallyLocked !== false ||
		vaultSupported !== true ||
		"vaultBinding" in input
	)
		throw Error(
			"Factory vault pool requires permanent unlocked vault configuration",
		);
	factoryTrustParameter(true, factoryPolicy);
	const validated = readPoolSettings(base);
	const settings: FactoryPoolSettings = {
		...validated,
		initiallyLocked: false,
		vaultSupported: true,
		factoryPolicy,
		stakingBuild,
		...(deployedProgram ? { deployedProgram } : {}),
	};
	const source = loadFactoryStakingSnapshot(undefined, stakingBuild);
	const asset = (a: { policyId: string; tokenNameHex: string }) =>
		new Constr(0, [a.policyId, a.tokenNameHex]);
	const derived: Script = {
		type: "PlutusV3",
		script: applyParamsToScript(source.template, [
			new Constr(0, [
				settings.bootstrapRef.txHash,
				BigInt(settings.bootstrapRef.outputIndex),
			]),
			settings.manager,
			settings.rewardsDistributor,
			asset(settings.stakingAsset),
			asset(settings.rewardAsset),
			new Constr(0, []),
			new Constr(1, []),
			new Constr(0, [factoryPolicy]),
		]),
	};
	const script = deployedProgram
		? selectExistingPoolProgram(deployedProgram, derived, source.blueprintHash)
		: derived;
	const policy = validatorToScriptHash(script);
	if (
		[
			factoryPolicy,
			settings.stakingAsset.policyId,
			settings.rewardAsset.policyId,
		].includes(policy)
	)
		throw Error("Pool identity collides with configured assets/factory");
	return {
		schema: "SINGLE-STAKING-FACTORY-POOL-PREPARATION-1" as const,
		settings,
		script,
		policy,
		address: validatorToAddress(settings.network, script),
		poolUnit: policy + "504f4f4c",
		initialDatum: encodePoolDatum({
			totalStaked: 0n,
			rewardDurationSeconds: 0n,
			periodFinishSeconds: 0n,
			rewardRate: 0n,
			lastUpdateSeconds: 0n,
			rewardPerTokenStored: 0n,
			accruedLiabilityBound: 0n,
			isPaused: false,
			isLocked: false,
		}),
		buildId: source.buildId,
		sourceHashes: source.manifest.files as Record<string, string>,
		compiledSourceVerified: true as const,
		inputHash: sha(
			Buffer.from(JSON.stringify({ settings, buildId: source.buildId })),
		),
		capabilities: source.manifest.capabilities as {
			vaultCreation: boolean;
			vaultStake: boolean;
			withdrawAndClaim: boolean;
		},
		stakingIntegrated: false as const,
		deploymentReady: false as const,
		executionEnabled: false as const,
	};
}
export type PreparedFactoryPool = ReturnType<typeof setupFactoryPool>;
