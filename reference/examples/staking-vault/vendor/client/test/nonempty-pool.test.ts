// Imported synthetic nonempty-pool fixture; genuine genesis lifecycle is tested separately.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { encodeData, hex, stateFromData } from "@ctvs/protocol";
import { Data, Emulator, type UTxO } from "@lucid-evolution/lucid";
import { prepareFactoryDeployment } from "../src/factory/deployment.ts";
import {
  constructFactoryFirstDeposit,
  type FirstDepositLedger,
} from "../src/factory/first-deposit.ts";
import { readFactorySettings } from "../src/setup/composed-settings.ts";
import { decodePoolDatum, encodePoolDatum } from "../src/staking/datum.ts";
import { decodeVaultPosition } from "../src/staking/position.ts";

async function fixture() {
  const settings = JSON.parse(
    await readFile(new URL("../../../profiles/preprod/settings.json", import.meta.url), "utf8"),
  );
  const prepared = prepareFactoryDeployment(readFactorySettings(settings));
  const { vault, pool } = prepared;
  const emulator = new Emulator([]);

  const add = (u: UTxO) => {
    emulator.ledger[u.txHash + u.outputIndex] = { utxo: u, spent: false };

    return u;
  };

  const address = settings.pool.fundingAddress;

  const ref = (n: string, index = 0) => ({
    txHash: n.repeat(32),
    outputIndex: index,
  });

  const config = add({
    ...ref("a1"),
    address: vault.source.lockAddress,
    assets: { lovelace: vault.input.configReserve, [vault.configUnit]: 1n },
    datum: Data.to(vault.configData),
  });
  const cert = add({
    ...ref("a2"),
    address: vault.source.lockAddress,
    assets: { lovelace: 3_000_000n, [vault.certificateUnit]: 1n },
    datum: Data.to(vault.registration),
  });
  const state = add({
    ...ref("a3"),
    address: vault.address,
    assets: { lovelace: vault.input.stateReserve, [vault.stateUnit]: 1n },
    datum: Data.to(vault.stateData),
  });
  const principal = settings.pool.stakingAsset.policyId + settings.pool.stakingAsset.tokenNameHex;
  const reward = settings.pool.rewardAsset.policyId + settings.pool.rewardAsset.tokenNameHex;
  const lower = 1_793_100_000_000n;
  const poolState = {
    ...decodePoolDatum(pool.initialDatum),
    totalStaked: 300_000_000n,
    periodFinishSeconds: lower / 1000n + 604800n,
    lastUpdateSeconds: lower / 1000n - 10n,
    rewardRate: 100n,
  };

  add({
    ...ref("a4"),
    address: pool.address,
    assets: {
      lovelace: 1_500_000n,
      [pool.poolUnit]: 1n,
      [principal]: 300_000_000n,
      [reward]: 100_000_000n,
    },
    datum: encodePoolDatum(poolState),
  });
  add({
    txHash: vault.input.poolBinding.positionSeed.txId,
    outputIndex: Number(vault.input.poolBinding.positionSeed.index),
    address,
    assets: { lovelace: 5_000_000n },
  });

  const controller = add({
    ...ref("a5"),
    address,
    assets: { lovelace: 100_000_000n },
    scriptRef: vault.script,
  });
  const staking = add({
    ...ref("a6"),
    address,
    assets: { lovelace: 100_000_000n },
    scriptRef: pool.script,
  });
  const funding = add({
    ...ref("a7"),
    address,
    assets: {
      lovelace: 100_000_000n,
      [principal]: 1_000_000_000n,
      [reward]: 20_000_000n,
    },
  });
  const collateral = add({
    ...ref("a8"),
    address,
    assets: { lovelace: 5_000_000n },
  });

  const toRef = (u: UTxO) => ({ txId: u.txHash, index: BigInt(u.outputIndex) });

  const input: FirstDepositLedger = {
    prepared,
    provider: emulator,
    fundingAddress: address,
    funding: [funding],
    collateral: [collateral],
    protectedInputs: [],
    configRef: toRef(config),
    certificateRef: toRef(cert),
    controllerReference: toRef(controller),
    stakingReference: toRef(staking),
    amount: 10_000_000n,
    lowerBoundMs: lower,
    reserveBuffer: 1_000_000n,
    maxNetworkFee: 3_000_000n,
    maxCollateralExposure: 5_000_000n,
  };

  return { input, config, cert, principal, reward, emulator, state };
}

test("factory-admitted first deposit into nonempty reward-bearing pool evaluates all four compiled purposes", async () => {
  const f = await fixture();
  const tx = await constructFactoryFirstDeposit(f.input);

  assert.equal(tx.effects.redeemers.length, 4);
  assert.ok(tx.finalEvaluation);
  assert.equal(tx.economicEffects.shares, 10_000_000_000_000n);
  assert.equal(tx.rewardEffects.contribution, 0n);
  assert.equal(stateFromData(tx.plan.outputs[0]!.datum!).backingAssets, 10_000_000n);
  assert.ok(tx.storage.poolTopup > 0n);

  const position = decodeVaultPosition(
    hex(encodeData(tx.plan.outputs[3]!.datum!)),
    f.input.prepared.vault.controller,
  );

  assert.equal(position.stakedAmount, 10_000_000n);
  assert.equal(position.pendingRewards, 0n);
  assert.equal(
    decodePoolDatum(hex(encodeData(tx.plan.outputs[2]!.datum!))).totalStaked,
    310_000_000n,
  );
  assert.ok(
    BigInt(tx.collateralCheck.exposureLovelace) >= BigInt(tx.collateralCheck.requiredLovelace),
  );
  assert.ok(tx.minimumAda.every((o) => BigInt(o.actualLovelace) >= BigInt(o.minimumLovelace)));
  assert.equal(tx.signed, false);
});

test("first deposit rejects substituted certificate, protected funding and wrong State", async () => {
  const f = await fixture();

  await assert.rejects(
    constructFactoryFirstDeposit({
      ...f.input,
      protectedInputs: [{ txId: f.input.funding[0]!.txHash, index: 0n }],
    }),
    /protected/,
  );
  f.cert.assets = {
    lovelace: 3_000_000n,
    ["ff".repeat(28) + f.input.prepared.vault.controller]: 1n,
  };
  await assert.rejects(constructFactoryFirstDeposit(f.input), /Unauthenticated/);
  f.state.address = f.input.fundingAddress;
  await assert.rejects(constructFactoryFirstDeposit(f.input), /Authenticated controller State/);
});
