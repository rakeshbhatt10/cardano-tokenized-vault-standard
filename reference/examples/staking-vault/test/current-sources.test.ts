import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import test from "node:test";
import { assertDeployedBlueprint } from "../src/contracts/blueprint.ts";
import { readVerifiedFactoryBuild } from "../vendor/client/src/factory/proof/build.ts";
import { loadFactoryProof } from "../vendor/client/src/factory/proof.ts";
import { unwrapStateRedeemer } from "../vendor/client/src/planning/model.ts";
import { loadFactoryStakingSnapshot } from "../vendor/client/src/setup/factory-pool.ts";

test("current example has no legacy helper tree or prototype factory selection", () => {
  for (const path of [
    "onchain/vault/lib/mixed_staking",
    "onchain/vault/lib/staking_ctvs1/mixed_state.ak",
    "onchain/vault/lib/staking_ctvs1/staking_decode.ak",
    "onchain/vault/lib/staking_ctvs1/staking_genesis.ak",
    "onchain/vault/lib/staking_ctvs1/cash_state.ak",
    "onchain/factory/validators/factory.ak",
    "onchain/factory/validators/identity_probe.ak",
    "vendor/client/src/factory/proof/identity.ts",
  ])
    assert.equal(existsSync(new URL(`../${path}`, import.meta.url)), false);

  assert.equal(
    existsSync(new URL("../onchain/vault/lib/staking_ctvs1/staking_state.ak", import.meta.url)),
    true,
  );
  assert.equal(loadFactoryProof().mode, "staking-vault");

  const wrongMode = "identity-probe" as Parameters<typeof loadFactoryProof>[0];

  assert.throws(() => loadFactoryProof(wrongMode), /Unsupported factory implementation/);

  const oldBuild = "interim-v1" as Parameters<typeof loadFactoryStakingSnapshot>[1];

  assert.throws(() => loadFactoryStakingSnapshot(undefined, oldBuild), /Unsupported staking build/);
  assert.throws(() => unwrapStateRedeemer({ constr: 0n, fields: [0n, 0n, 0n] }));
});
test("source selection covers current code and retains exactly the deployed factory/controller handlers", () => {
  const original = readVerifiedFactoryBuild();
  const current = {
    validators: original.blueprint.validators.filter((validator) =>
      original.sourceSelection.validatorTitles.includes(validator.title),
    ),
  };

  assert.equal(
    assertDeployedBlueprint(current, original.blueprint, original.sourceSelection.validatorTitles)
      .length,
    6,
  );

  const changed = structuredClone(current);
  const first = changed.validators[0];

  assert.ok(first);
  first.compiledCode = "00";
  assert.throws(
    () =>
      assertDeployedBlueprint(
        changed,
        original.blueprint,
        original.sourceSelection.validatorTitles,
      ),
    /differs from deployed/,
  );
  assert.throws(
    () =>
      assertDeployedBlueprint(
        original.blueprint,
        original.blueprint,
        original.sourceSelection.validatorTitles,
      ),
    /Unexpected current factory validator set/,
  );
});
