import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { constructFactoryFirstDeposit, constructFactoryMint } from "../src/index.ts";
import { firstDepositInput } from "../src/local/inputs.ts";
import { runLocalLifecycle } from "../src/local/lifecycle.ts";
import { setupLocalExample } from "../src/local/setup.ts";
import { historicalProfile, readFactoryRecord } from "../src/profile.ts";
import { setupFactoryPool } from "../vendor/client/src/setup/factory-pool.ts";
import { decodePoolDatum } from "../vendor/client/src/staking/datum.ts";

test("public profile reproduces deployed policies and authenticated genesis datums without claiming live verification", () => {
  const p = historicalProfile();

  assert.equal(
    p.prepared.vault.controller,
    "8a1c4096b69a097740e16479348fb2d74862925d740d4dd343508657",
  );
  assert.equal(p.prepared.pool.policy, "02f13369acbfc717f811413691d54df7aabc43ce3d8355265b298c36");
  assert.equal(p.factory.factoryPolicy, "9ca7570e34603c08370ac69d204ebdf9651d4b6bdd193918adc43370");
  assert.equal(p.liveIdentityVerified, false);
  assert.equal(p.deploymentReady, false);
});
test("complete unsigned lifecycle mints authentic registration and covers reward-bearing top-up, partial/full exits and reusable position", async () => {
  const result = await runLocalLifecycle();

  assert.equal(result.records.length, 14);
  assert.equal(result.finalBacking, 0n);
  assert.equal(result.finalSupply, 0n);
  assert.equal(result.signed, false);
  assert.equal(result.submitted, false);
  assert.ok(result.rewards.topup.contribution > 0n);
  assert.ok(result.rewards.withdraw.remainingReserve > 0n);
  assert.ok(result.rewards.redeem.receipt > 0n);

  for (const record of result.records) {
    assert.ok(record.estimatedSignedBytes <= 16384);

    if (!record.stage.startsWith("publish-")) {
      assert.ok(record.finalEvaluation);
      assert.ok("minimumAda" in record && "collateralCheck" in record);
    }
  }
});
test("pool binding rejects source, manager, factory, reward and lock substitution", () => {
  const settings = historicalProfile().prepared.pool.settings;

  for (const changed of [
    { ...settings, manager: "11".repeat(28) },
    { ...settings, factoryPolicy: "22".repeat(28) },
    { ...settings, initiallyLocked: true },
    { ...settings, stakingBuild: "interim-v1" },
    { ...settings, rewardAsset: { ...settings.rewardAsset, tokenNameHex: "aa" } },
  ])
    assert.throws(() => setupFactoryPool(changed as typeof settings));
});
test("factory import rejects wrong network, identity and duplicated references", () => {
  const prepared = historicalProfile().prepared;
  const record = JSON.parse(
    readFileSync(new URL("../profiles/preprod/factory.json", import.meta.url), "utf8"),
  );

  assert.throws(() => readFactoryRecord({ ...record, network: "Preview" }, prepared));
  assert.throws(() => readFactoryRecord({ ...record, factoryPolicy: "11".repeat(28) }, prepared));
  assert.throws(() =>
    readFactoryRecord(
      { ...record, stages: [record.stages[0], record.stages[0], record.stages[0]] },
      prepared,
    ),
  );
});
test("first entry rejects substituted certificate, protected funds, wrong State and duplicate State evidence", async () => {
  const f = await setupLocalExample();
  const input = await firstDepositInput(f);
  const funding = input.funding[0];

  assert.ok(funding);
  await assert.rejects(
    constructFactoryFirstDeposit({
      ...input,
      protectedInputs: [{ txId: funding.txHash, index: BigInt(funding.outputIndex) }],
    }),
    /protected/,
  );

  const cert = f.ledger.output(f.certificate.txHash, f.certificate.outputIndex);
  const original = structuredClone(cert.assets);

  cert.assets = { lovelace: 4_000_000n, ["ff".repeat(28) + f.prepared.vault.controller]: 1n };
  await assert.rejects(constructFactoryFirstDeposit(input), /Unauthenticated/);
  cert.assets = original;

  const state = await f.ledger.provider.getUtxoByUnit(f.prepared.vault.stateUnit);
  const originalAddress = state.address;

  state.address = f.ledger.address;
  await assert.rejects(constructFactoryFirstDeposit(input), /Authenticated controller State/);
  state.address = originalAddress;
  f.ledger.add({ ...state, txHash: "99".repeat(32) });
  await assert.rejects(constructFactoryFirstDeposit(input));
});
test("first deposit changes only its principal delta in the global pool total", async () => {
  const f = await setupLocalExample();
  const tx = await constructFactoryFirstDeposit(await firstDepositInput(f));

  assert.equal(tx.effects.redeemers.length, 4);
  f.ledger.advance(tx.cbor);

  const pool = await f.ledger.provider.getUtxoByUnit(f.prepared.pool.poolUnit);

  assert.ok(pool.datum);
  assert.equal(decodePoolDatum(pool.datum).totalStaked, 10_000_000n);

  const mint = {
    ...(await firstDepositInput(f)),
    shares: 10_000_000_000_000n,
    maxAssets: 10_000_000n,
    maxRewardInput: 100_000n,
    lowerBoundMs: f.time + 660000n,
  };

  await assert.rejects(constructFactoryMint({ ...mint, maxAssets: 1n }), /user bound/);
  await assert.rejects(
    constructFactoryMint({ ...mint, maxRewardInput: 0n }),
    /Reward contribution\/receipt bound/,
  );
});
