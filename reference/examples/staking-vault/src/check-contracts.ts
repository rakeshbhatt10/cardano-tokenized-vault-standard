/** Rebuild both complete programs without replacing imported attestations or blueprints. */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { readVerifiedFactoryBuild } from "../vendor/client/src/factory/proof/build.ts";
import { loadFactoryStakingSnapshot } from "../vendor/client/src/setup/factory-pool.ts";
import { assertDeployedBlueprint } from "./contracts/blueprint.ts";
import {
  bindConfigLock,
  referenceRoot,
  seedCache,
  stageFactory,
  stageStaking,
} from "./contracts/stage.ts";

const factory = readVerifiedFactoryBuild();
const staking = loadFactoryStakingSnapshot();
const target = join(referenceRoot, ".build/staking-vault-example");
const artifacts = join(referenceRoot, "artifacts/staking-vault/contracts");

const sha = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

function compiler(binary: string, expected: string) {
  const actual = execFileSync(binary, ["--version"], { encoding: "utf8" }).trim();

  if (actual !== expected) throw Error(`Compiler mismatch: expected ${expected}; found ${actual}`);

  return binary;
}

function build(binary: string, directory: string, args: string[]) {
  execFileSync(binary, ["build", ...args], { cwd: directory, stdio: "inherit" });

  return readFileSync(join(directory, "plutus.json"));
}

function check(binary: string, directory: string, name: string, expected: number) {
  const stdout = execFileSync(binary, ["check", "--seed", "3098115174"], {
    cwd: directory,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  const report = JSON.parse(stdout.slice(stdout.indexOf("{")));

  if (
    report.summary.failed !== 0 ||
    report.summary.total !== expected ||
    report.summary.passed !== expected
  )
    throw Error("Contract checks failed or coverage changed");

  writeFileSync(join(artifacts, `${name}-checks.json`), `${JSON.stringify(report, null, 2)}\n`);

  return report.summary;
}

const factoryCompiler = compiler(process.env.AIKEN_FACTORY ?? "aiken", "aiken v1.1.22+39d6b04");
const stakingCompiler = compiler(
  process.env.AIKEN_STAKING ?? "aiken-1.1.23",
  "aiken v1.1.23+unknown",
);

rmSync(target, { recursive: true, force: true });
mkdirSync(artifacts, { recursive: true });

const factoryDirectory = join(target, "factory");
const stakingDirectory = join(target, "staking");

stageFactory(factoryDirectory);
stageStaking(stakingDirectory);
seedCache(factoryDirectory);
seedCache(stakingDirectory);

const flags = ["--trace-level", "silent", "--include-all-types", "--deny"];

build(factoryCompiler, factoryDirectory, flags);
bindConfigLock(factoryDirectory, factory.manifest.configLock);

const factoryBytes = build(factoryCompiler, factoryDirectory, flags);

const currentPrograms = assertDeployedBlueprint(
  JSON.parse(factoryBytes.toString()),
  factory.blueprint,
  factory.sourceSelection.validatorTitles,
);

const stakingBytes = build(stakingCompiler, stakingDirectory, []);

const stakingPrograms = assertDeployedBlueprint(
  JSON.parse(stakingBytes.toString()),
  JSON.parse(readFileSync(staking.blueprintPath, "utf8")),
  staking.manifest.validatorTitles,
  "staking",
);

const report = {
  schema: "CTVS-STAKING-REBUILD-1",
  factory: {
    compiler: "aiken v1.1.22+39d6b04",
    blueprintSha256: sha(factoryBytes),
    sourceSelectionSha256: factory.sourceSelectionSha256,
    programs: currentPrograms,
    summary: check(
      factoryCompiler,
      factoryDirectory,
      "factory",
      factory.sourceSelection.factoryChecks,
    ),
  },
  staking: {
    compiler: "aiken v1.1.23+unknown",
    blueprintSha256: sha(stakingBytes),
    programs: stakingPrograms,
    summary: check(stakingCompiler, stakingDirectory, "staking", staking.manifest.compilerChecks),
  },
  currentProgramsByteIdentical: true,
  wholeFactoryBlueprintByteIdentical: false,
  wholeStakingBlueprintByteIdentical: false,
  deploymentReady: false,
};

writeFileSync(join(artifacts, "rebuild.json"), `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(report, null, 2));
