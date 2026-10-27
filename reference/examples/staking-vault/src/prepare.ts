/** Offline export only. Provider-resolved UTxOs are required for transaction construction. */
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { Data } from "@lucid-evolution/lucid";
import { prepareFactoryDeployment, readFactorySettings } from "./index.ts";
import { historicalProfile, publicJson, readFactoryRecord } from "./profile.ts";

const [settingsPath, factoryPath, outputPath] = process.argv.slice(2);

if (!settingsPath || !factoryPath || !outputPath)
  throw Error(
    "Usage: vault:prepare <settings.json> <factory-deployment.json> <new-output-directory>",
  );

const settings = readFactorySettings(JSON.parse(await readFile(resolve(settingsPath), "utf8")));
const historical = historicalProfile().prepared;

if (
  settings.vault.seed.txId === historical.vault.input.seed.txId ||
  settings.positionSeed.txId === historical.vault.input.poolBinding.positionSeed.txId
)
  throw Error(
    "Historical creation seeds are spent; supply freshly resolved vault and position seeds",
  );

const prepared = prepareFactoryDeployment(settings);
const factory = readFactoryRecord(
  JSON.parse(await readFile(resolve(factoryPath), "utf8")),
  prepared,
);
const files: Record<string, string> = {
  "settings.json": await readFile(resolve(settingsPath), "utf8"),
  "factory-import.json": publicJson(factory),
  "controller-script.json": publicJson(prepared.vault.script),
  "staking-script.json": publicJson(prepared.pool.script),
  "factory-script.json": publicJson(prepared.vault.source.script),
  "config-lock-script.json": publicJson(prepared.vault.source.lock),
  "config.datum.cbor": `${Data.to(prepared.vault.configData)}\n`,
  "state.datum.cbor": `${Data.to(prepared.vault.stateData)}\n`,
  "expected-registration.datum.cbor": `${Data.to(prepared.vault.registration)}\n`,
  "preparation.json": publicJson({
    schema: "CTVS-STAKING-EXAMPLE-PREPARATION-1",
    controller: prepared.vault.controller,
    vaultAddress: prepared.vault.address,
    poolPolicy: prepared.pool.policy,
    poolAddress: prepared.pool.address,
    stateUnit: prepared.vault.stateUnit,
    configUnit: prepared.vault.configUnit,
    expectedCertificateUnit: prepared.vault.certificateUnit,
    factoryPolicy: factory.factoryPolicy,
    buildId: factory.buildId,
    stakingBuildId: prepared.pool.buildId,
    sourceHashes: {
      factory: prepared.vault.source.sourceHashes,
      staking: prepared.pool.sourceHashes,
    },
    seedsLiveVerified: false,
    networkVerified: false,
    registrationMinted: false,
    signed: false,
    submitted: false,
    deploymentReady: false,
  }),
};

await mkdir(resolve(outputPath), { recursive: false });

for (const [name, bytes] of Object.entries(files))
  await writeFile(resolve(outputPath, name), bytes, { flag: "wx" });

const hashes = Object.fromEntries(
  Object.entries(files).map(([name, bytes]) => [
    name,
    createHash("sha256").update(bytes).digest("hex"),
  ]),
);

await writeFile(resolve(outputPath, "SHA256SUMS.json"), publicJson(hashes), { flag: "wx" });
console.log(
  publicJson({
    directory: resolve(outputPath),
    controller: prepared.vault.controller,
    signed: false,
    submitted: false,
    deploymentReady: false,
  }),
);
