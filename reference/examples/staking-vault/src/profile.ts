import { readFileSync } from "node:fs";
import { Data } from "@lucid-evolution/lucid";
import { z } from "zod";
import { prepareFactoryDeployment, readFactorySettings } from "./index.ts";

const hash = (length: number) => z.string().regex(new RegExp(`^[0-9a-f]{${length * 2}}$`));

const reference = z.object({ txId: hash(32), index: z.string().regex(/^(0|[1-9][0-9]*)$/) });
const factorySchema = z.object({
  network: z.enum(["Preview", "Preprod"]),
  networkMagic: z.number().int(),
  factoryPolicy: hash(28),
  buildId: hash(32),
  stages: z.array(z.object({ stage: z.enum(["factory", "prefix0", "prefix1"]), reference })),
});

export function readFactoryRecord(
  value: unknown,
  prepared: ReturnType<typeof prepareFactoryDeployment>,
) {
  const factory = factorySchema.parse(value);
  const names = new Set(factory.stages.map((stage) => stage.stage));
  const refs = new Set(
    factory.stages.map((stage) => `${stage.reference.txId}#${stage.reference.index}`),
  );
  const magic = prepared.vault.input.network === "Preprod" ? 1 : 2;

  if (
    factory.network !== prepared.vault.input.network ||
    factory.networkMagic !== magic ||
    factory.factoryPolicy !== prepared.vault.source.policy ||
    factory.buildId !== prepared.vault.source.buildId ||
    factory.stages.length !== 3 ||
    names.size !== 3 ||
    refs.size !== 3
  )
    throw Error("Factory record network/source/identity/references mismatch");

  return { ...factory, liveReferencesVerified: false, networkVerified: false };
}

export function publicJson(value: unknown): string {
  return (
    JSON.stringify(value, (_, field) => (typeof field === "bigint" ? String(field) : field), 2) +
    "\n"
  );
}

export function historicalProfile() {
  const read = (name: string) =>
    JSON.parse(readFileSync(new URL(`../profiles/preprod/${name}.json`, import.meta.url), "utf8"));

  const prepared = prepareFactoryDeployment(readFactorySettings(read("settings")));
  const factory = readFactoryRecord(read("factory"), prepared);
  const vault = z
    .object({
      controller: hash(28),
      vaultAddress: z.string(),
      factoryPolicy: hash(28),
      poolPolicy: hash(28),
      buildId: hash(32),
      outputs: z.array(
        z.object({ index: z.number(), unit: z.string(), address: z.string(), datum: z.string() }),
      ),
    })
    .parse(read("vault"));
  const pool = z
    .object({
      poolPolicyId: hash(28),
      poolAddress: z.string(),
      factoryPolicy: hash(28),
      factoryBuildId: hash(32),
    })
    .parse(read("pool"));

  if (
    vault.controller !== prepared.vault.controller ||
    vault.vaultAddress !== prepared.vault.address ||
    vault.factoryPolicy !== factory.factoryPolicy ||
    vault.poolPolicy !== prepared.pool.policy ||
    vault.buildId !== factory.buildId ||
    pool.poolPolicyId !== prepared.pool.policy ||
    pool.poolAddress !== prepared.pool.address ||
    pool.factoryPolicy !== factory.factoryPolicy ||
    pool.factoryBuildId !== factory.buildId
  )
    throw Error("Historical deployment profile binding changed");

  verifyGenesisOutputs(prepared, vault.outputs);

  return {
    prepared,
    factory,
    vault,
    pool,
    historicalOnly: true,
    liveIdentityVerified: false,
    deploymentReady: false,
  };
}

function verifyGenesisOutputs(
  prepared: ReturnType<typeof prepareFactoryDeployment>,
  outputs: { index: number; unit: string; address: string; datum: string }[],
) {
  const datums = [
    Data.to(prepared.vault.configData),
    Data.to(prepared.vault.stateData),
    Data.to(prepared.vault.registration),
  ];
  const units = [
    prepared.vault.configUnit,
    prepared.vault.stateUnit,
    prepared.vault.certificateUnit,
  ];

  for (let index = 0; index < 3; index++) {
    const output = outputs.find((item) => item.index === index);

    if (
      !output ||
      output.datum !== datums[index] ||
      output.unit !== units[index] ||
      output.address !== (index === 1 ? prepared.vault.address : prepared.vault.source.lockAddress)
    )
      throw Error("Historical Config/State/certificate changed");
  }
}
