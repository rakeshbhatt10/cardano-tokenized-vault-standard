import { verifyUpstream } from "../../ctvs2-liquid/src/provenance.ts";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	cpSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	readdirSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../", import.meta.url));
const pkg = join(root, "packages/staking-ctvs1-vault");
const source = join(pkg, "factory/onchain");
const staging = mkdtempSync(join(tmpdir(), "vault-factory-proof-"));
const compiler = join(root, ".local-tools/aiken-1.1.22/aiken");
const hash = (b: Uint8Array) => createHash("sha256").update(b).digest("hex");
const sources: Record<string, string> = {};
function copy(from: string, to: string) {
	mkdirSync(to, { recursive: true });
	for (const e of readdirSync(from, { withFileTypes: true })) {
		if (e.isSymbolicLink()) throw Error("Unexpected symlink");
		const a = join(from, e.name),
			b = join(to, e.name);
		if (e.isDirectory()) copy(a, b);
		else {
			const bytes = readFileSync(a);
			sources[relative(root, a)] = hash(bytes);
			writeFileSync(b, bytes);
		}
	}
}
try {
	const upstream = verifyUpstream();
	if (
		execFileSync(compiler, ["--version"], { encoding: "utf8" }).trim() !==
		"aiken v1.1.22+39d6b04"
	)
		throw Error("Compiler mismatch");
	copy(source, staging);
	copy(
		join(root, "vendor/ctvs-reference/packages/onchain/lib/ctvs"),
		join(staging, "lib/ctvs"),
	);
	for (const folder of ["staking_ctvs1", "mixed_staking", "staking"])
		copy(join(pkg, "onchain/lib", folder), join(staging, "lib", folder));
	const cache = join(
		root,
		"vendor/ctvs-reference/.build/dependency-cache/packages",
	);
	if (existsSync(cache))
		cpSync(cache, join(staging, "build/packages"), { recursive: true });
	writeFileSync(
		join(staging, "lib/ctvs/deployment.ak"),
		`pub const config_lock_hash: ByteArray = #"${"00".repeat(28)}"\npub const claim_hash: ByteArray = #"${"00".repeat(28)}"\n`,
	);
	// Run the unchanged shared vectors through the optimized full controller decoder.
	// Golden byte/operation assertions remain; only the final decoder under test changes.
	const vectors = readFileSync(
		join(staging, "lib/mixed_staking/authorization_test.ak"),
		"utf8",
	)
		.replace(
			"use mixed_staking/authorization",
			"use mixed_staking/authorization\nuse staking_ctvs1/controller_decode\nuse ctvs/validation",
		)
		.replaceAll(
			/when authorization\.decode\(raw\) is \{[\s\S]*?\n  \}/g,
			"let (action, _, _) = controller_decode.decode(raw)\n  validation.valid_state_action(action)",
		);
	if (!vectors.includes("controller_decode.decode(raw)"))
		throw Error("Shared vector format changed");
	writeFileSync(
		join(staging, "lib/staking_ctvs1/controller_vectors_test.ak"),
		vectors,
	);
	const build = () =>
		execFileSync(
			compiler,
			["build", "--trace-level", "silent", "--include-all-types", "--deny"],
			{ cwd: staging, stdio: "inherit" },
		);
	execFileSync(compiler, ["fmt", "--check"], { cwd: source, stdio: "inherit" });
	build();
	const blueprint = () =>
		JSON.parse(readFileSync(join(staging, "plutus.json"), "utf8"));
	const lock = blueprint().validators.find(
		(v: { title: string }) => v.title === "config_lock.config_lock.else",
	);
	if (!lock) throw Error("Missing config lock");
	writeFileSync(
		join(staging, "lib/factory/deployment.ak"),
		`pub const config_lock: ByteArray = #"${lock.hash}"\n`,
	);
	writeFileSync(
		join(staging, "lib/ctvs/deployment.ak"),
		`pub const config_lock_hash: ByteArray = #"${lock.hash}"\npub const claim_hash: ByteArray = #"${"00".repeat(28)}"\n`,
	);
	build();
	if (
		blueprint().validators.find(
			(v: { title: string }) => v.title === lock.title,
		).hash !== lock.hash
	)
		throw Error("Config lock cycle");
	const checkOutput = execFileSync(
		compiler,
		["check", "--seed", "3098115174"],
		{ cwd: staging, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
	);
	const checks = JSON.parse(checkOutput.slice(checkOutput.indexOf("{")));
	if (checks.summary.failed !== 0)
		throw new Error("Factory component checks failed");
	const out = join(pkg, "artifacts/factory");
	mkdirSync(out, { recursive: true });
	const bytes = readFileSync(join(staging, "plutus.json"));
	writeFileSync(join(out, "blueprint.json"), bytes);
	const checkBytes = Buffer.from(JSON.stringify(checks, null, 2) + "\n");
	writeFileSync(join(out, "checks.json"), checkBytes);
	writeFileSync(
		join(out, "build.json"),
		JSON.stringify(
			{
				schema: "FACTORY-IDENTITY-PROOF-BUILD-1",
				upstream,
				checksSha256: hash(checkBytes),
				summary: checks.summary,
				compiler: "aiken v1.1.22+39d6b04",
				sources,
				blueprintSha256: hash(bytes),
				buildScriptSha256: hash(readFileSync(fileURLToPath(import.meta.url))),
				configLock: lock.hash,
				scope:
					"FACTORY-01 identity proof plus size-optimized mixed-vault controller",
				deploymentReady: false,
				executionEnabled: false,
			},
			null,
			2,
		) + "\n",
	);
	console.log(
		JSON.stringify({
			artifactDirectory: out,
			scope:
				"compiled factory and economic controller; full staking lifecycle unproved",
			validators: blueprint().validators.map(
				(v: { title: string; compiledCode: string }) => ({
					title: v.title,
					bytes: v.compiledCode.length / 2,
				}),
			),
		}),
	);
} finally {
	if (process.env.KEEP_FACTORY_STAGING === "1") console.error(staging);
	else rmSync(staging, { recursive: true, force: true });
}
