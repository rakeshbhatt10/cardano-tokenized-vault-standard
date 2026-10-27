import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

test("offline preparation rejects spent profile seeds, exports public drafts for new seeds and refuses overwrite", async () => {
  const directory = await mkdtemp(join(tmpdir(), "ctvs-staking-prepare-"));

  try {
    const input = JSON.parse(
      await readFile(new URL("../profiles/preprod/settings.json", import.meta.url), "utf8"),
    );
    const settings = join(directory, "settings.json");
    const output = join(directory, "draft");

    const run = () =>
      spawnSync(
        process.execPath,
        [
          "--import",
          "tsx",
          fileURLToPath(new URL("../src/prepare.ts", import.meta.url)),
          settings,
          fileURLToPath(new URL("../profiles/preprod/factory.json", import.meta.url)),
          output,
        ],
        { encoding: "utf8" },
      );

    await writeFile(settings, JSON.stringify(input));

    const spent = run();

    assert.notEqual(spent.status, 0);
    assert.match(spent.stderr, /Historical creation seeds are spent/);
    input.vault.seed = { txId: "71".repeat(32), index: "0" };
    input.positionSeed = { txId: "72".repeat(32), index: "0" };
    await writeFile(settings, JSON.stringify(input));

    const result = run();

    assert.equal(result.status, 0, result.stderr);

    const prepared = JSON.parse(await readFile(join(output, "preparation.json"), "utf8"));

    assert.equal(prepared.registrationMinted, false);
    assert.equal(prepared.seedsLiveVerified, false);
    assert.equal(prepared.deploymentReady, false);
    assert.equal(prepared.signed, false);
    assert.ok(await readFile(join(output, "SHA256SUMS.json"), "utf8"));
    assert.notEqual(run().status, 0);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
