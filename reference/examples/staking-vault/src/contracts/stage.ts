import { cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
export const exampleRoot = fileURLToPath(new URL("../../", import.meta.url));
export const referenceRoot = fileURLToPath(new URL("../../../../", import.meta.url));

export function stageFactory(directory: string) {
  cpSync(join(exampleRoot, "onchain/factory"), directory, { recursive: true });
  mkdirSync(join(directory, "lib/ctvs"), { recursive: true });
  cpSync(join(referenceRoot, "packages/onchain/lib/ctvs"), join(directory, "lib/ctvs"), {
    recursive: true,
  });

  for (const name of ["staking_ctvs1", "staking"])
    cpSync(join(exampleRoot, "onchain/vault/lib", name), join(directory, "lib", name), {
      recursive: true,
    });

  const vectors = readFileSync(join(directory, "lib/staking/authorization_test.ak"), "utf8")
    .replace(
      "use staking/authorization",
      "use staking/authorization\nuse staking_ctvs1/controller_decode\nuse ctvs/validation",
    )
    .replaceAll(
      /when authorization\.decode\(raw\) is \{[\s\S]*?\n {2}\}/g,
      "let (action, _, _) = controller_decode.decode(raw)\n  validation.valid_state_action(action)",
    );

  if (!vectors.includes("controller_decode.decode(raw)")) throw Error("Shared vectors changed");

  writeFileSync(join(directory, "lib/staking_ctvs1/controller_vectors_test.ak"), vectors);
  bindConfigLock(directory, "00".repeat(28));
}

export function bindConfigLock(directory: string, hash: string) {
  writeFileSync(
    join(directory, "lib/ctvs/deployment.ak"),
    `pub const config_lock_hash: ByteArray = #"${hash}"\npub const claim_hash: ByteArray = #"${"00".repeat(28)}"\n`,
  );
}

export function stageStaking(directory: string) {
  mkdirSync(directory, { recursive: true });

  for (const name of ["aiken.toml", "aiken.lock", "lib", "validators"])
    cpSync(join(exampleRoot, "onchain/staking", name), join(directory, name), { recursive: true });
}

export function seedCache(directory: string) {
  const cache = join(referenceRoot, ".build/dependency-cache/packages");

  if (existsSync(cache)) cpSync(cache, join(directory, "build/packages"), { recursive: true });
}
