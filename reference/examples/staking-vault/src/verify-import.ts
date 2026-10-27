import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { readVerifiedFactoryBuild } from "../vendor/client/src/factory/proof/build.ts";
import { loadFactoryStakingSnapshot } from "../vendor/client/src/setup/factory-pool.ts";

const root = fileURLToPath(new URL("../", import.meta.url));
const bindingSchema = z.object({
  vendorSha256: z.record(z.string(), z.string().regex(/^[0-9a-f]{64}$/)),
});

function inventory(directory: string, prefix = ""): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isSymbolicLink()) throw Error("Imported client symlink rejected");

    const name = join(prefix, entry.name);

    return entry.isDirectory() ? inventory(join(directory, entry.name), name) : [name];
  });
}

export function verifyImportedSources() {
  const provenance = bindingSchema.parse(
    JSON.parse(readFileSync(join(root, "provenance.json"), "utf8")),
  );
  const client = join(root, "vendor/client");
  const actual = inventory(client).sort();

  if (JSON.stringify(actual) !== JSON.stringify(Object.keys(provenance.vendorSha256).sort()))
    throw Error("Imported client inventory changed");

  for (const [path, digest] of Object.entries(provenance.vendorSha256)) {
    if (
      path.startsWith("/") ||
      path.split("/").includes("..") ||
      createHash("sha256")
        .update(readFileSync(join(client, path)))
        .digest("hex") !== digest
    )
      throw Error(`Imported client binding changed: ${path}`);
  }

  const factory = readVerifiedFactoryBuild();
  const staking = loadFactoryStakingSnapshot();

  return {
    factoryBuildId: factory.buildId,
    stakingBuildId: staking.buildId,
    verifiedImportedBytes: true,
    recompiledThisRun: false,
  };
}
