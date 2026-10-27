import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";
import { loadFactoryStakingSnapshot } from "../vendor/client/src/setup/factory-pool.ts";

test("staking documentation uses current names and preserves the exact ABI and current compiler inventory", () => {
  const read = (path: string) =>
    JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), "utf8"));

  for (const path of [
    "onchain/staking/FRAC-MIXED-OWNER-STATUS.md",
    "onchain/staking/MIXED-OWNER-AUTHORIZATION.md",
    "onchain/staking/MIXED-OWNER-INTERFACE.json",
    "onchain/staking/scripts/export-mixed-owner.py",
    "vendor/client/protocol/shared-v1/contract.json",
    "evidence/staking/STAKING-IMPORT-STATUS.md",
  ])
    assert.equal(existsSync(new URL(`../${path}`, import.meta.url)), false);

  const { status: currentStatus, ...current } = read("docs/STAKING-INTERFACE.json");
  const { status: originalStatus, ...original } = read("evidence/staking/imported-interface.json");

  assert.notEqual(currentStatus, originalStatus);
  assert.deepEqual(current, original);

  const origin = read("evidence/staking/import-snapshot.json");
  const source = loadFactoryStakingSnapshot();

  assert.equal(
    source.manifest.originSnapshotSha256,
    "52c966c171f82f16f83bf4bbee12570e01ebb6c74d5868be96658dd308fceeb2",
  );

  for (const [path, digest] of Object.entries(origin.files)) {
    if (path.endsWith(".ak") && path !== "validators/token.ak") {
      assert.ok(source.manifest.files[path]);

      if (path !== "validators/single_staking.ak")
        assert.equal(source.manifest.files[path], digest);
    }

    if (path === "aiken.lock") assert.equal(source.manifest.files[path], digest);
  }

  assert.equal(source.blueprintHash, origin.files["plutus.json"]);
  assert.equal(source.manifest.compilerChecks, 254);
  assert.equal(source.manifest.files["validators/token.ak"], undefined);

  assert.ok(source.manifest.exampleFiles["docs/STAKING-AUTHORIZATION.md"]);
  assert.equal(
    source.manifest.exampleFiles["evidence/staking/STAKING-IMPORT-STATUS.md"],
    undefined,
  );
});
