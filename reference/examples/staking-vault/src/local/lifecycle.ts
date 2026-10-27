import assert from "node:assert/strict";
import { decodeData, stateFromData } from "@ctvs/protocol";
import { positionName } from "../../vendor/client/src/planning/operation.ts";
import { decodeVaultPosition } from "../../vendor/client/src/staking/position.ts";
import {
  constructFactoryExistingDeposit,
  constructFactoryFirstDeposit,
  constructFactoryRedeem,
  constructFactoryWithdraw,
} from "../index.ts";
import { constructFactoryMint } from "../mint.ts";
import { outRef } from "./ledger.ts";
import { setupLocalExample } from "./setup.ts";

export async function runLocalLifecycle() {
  const f = await setupLocalExample();
  const { ledger, prepared } = f;

  const funding = async () =>
    (await ledger.provider.getUtxos(ledger.address)).filter(
      (u) =>
        !u.datum &&
        !u.scriptRef &&
        u.txHash !== f.collateral.txHash &&
        u.txHash !== prepared.vault.input.poolBinding.positionSeed.txId,
    );

  const common = {
    prepared,
    provider: ledger.provider,
    fundingAddress: ledger.address,
    collateral: [f.collateral],
    protectedInputs: [],
    configRef: outRef(f.config),
    controllerReference: outRef(f.controller),
    stakingReference: outRef(f.staking),
    reserveBuffer: 1_000_000n,
    maxNetworkFee: 3_000_000n,
    maxCollateralExposure: 5_000_000n,
  };
  const first = await constructFactoryFirstDeposit({
    ...common,
    funding: await funding(),
    certificateRef: outRef(f.certificate),
    amount: 10_000_000n,
    lowerBoundMs: f.time + 60000n,
  });

  ledger.advance(first.cbor);
  f.records.push({ stage: "first-deposit", ...first });

  const topup = await constructFactoryMint({
    ...common,
    funding: await funding(),
    shares: 10_000_000_000_000n,
    maxAssets: 10_000_000n,
    maxRewardInput: 100_000n,
    lowerBoundMs: f.time + 660000n,
  });

  assert.equal(topup.plan.operation, "mint");
  assert.equal(topup.economicEffects.shares, 10_000_000_000_000n);
  ledger.advance(topup.cbor);
  f.records.push({ stage: "mint-top-up-with-reward-equalization", ...topup });

  const withdraw = await constructFactoryWithdraw({
    ...common,
    funding: await funding(),
    assets: 5_000_000n,
    maxShares: 5_000_000_000_000n,
    lowerBoundMs: f.time + 1260000n,
  });

  ledger.advance(withdraw.cbor);
  f.records.push({ stage: "partial-withdraw-and-claim", ...withdraw });

  const redeem = await constructFactoryRedeem({
    ...common,
    funding: await funding(),
    shares: 15_000_000_000_000n,
    lowerBoundMs: f.time + 1860000n,
  });

  ledger.advance(redeem.cbor);
  f.records.push({ stage: "full-redeem-and-claim", ...redeem });

  const reentry = await constructFactoryExistingDeposit({
    ...common,
    funding: await funding(),
    assets: 10_000_000n,
    minShares: 10_000_000_000_000n,
    maxRewardInput: 0n,
    lowerBoundMs: f.time + 2460000n,
  });

  ledger.advance(reentry.cbor);
  f.records.push({ stage: "re-entry-reuses-position", ...reentry });

  const final = await constructFactoryWithdraw({
    ...common,
    funding: await funding(),
    assets: 10_000_000n,
    maxShares: 10_000_000_000_000n,
    lowerBoundMs: f.time + 3060000n,
  });

  ledger.advance(final.cbor);
  f.records.push({ stage: "full-fixed-asset-withdraw-and-claim", ...final });

  return localReport(f, {
    topup: topup.rewardEffects,
    withdraw: withdraw.rewardEffects,
    redeem: redeem.rewardEffects,
    final: final.rewardEffects,
  });
}

type Rewards = Awaited<ReturnType<typeof constructFactoryRedeem>>["rewardEffects"];

async function localReport(
  f: Awaited<ReturnType<typeof setupLocalExample>>,
  rewards: Record<"topup" | "withdraw" | "redeem" | "final", Rewards>,
) {
  const { ledger, prepared } = f;
  const state = await ledger.provider.getUtxoByUnit(prepared.vault.stateUnit);

  assert.ok(state.datum);

  const core = stateFromData(decodeData(state.datum));

  assert.equal(core.backingAssets, 0n);
  assert.equal(core.economicSupply, 0n);

  const marker = prepared.pool.policy + positionName(prepared.vault.input.poolBinding.positionSeed);
  const position = await ledger.provider.getUtxoByUnit(marker);

  assert.ok(position.datum);
  assert.equal(decodeVaultPosition(position.datum, prepared.vault.controller).stakedAmount, 0n);
  assert.ok(rewards.withdraw.receipt > 0n);
  assert.ok(rewards.redeem.receipt > 0n);

  return {
    schema: "CTVS-STAKING-LOCAL-LIFECYCLE-1",
    synthetic: true,
    signed: false,
    submitted: false,
    nodeAcceptanceVerified: false,
    deploymentReady: false,
    controller: prepared.vault.controller,
    factoryPolicy: prepared.vault.source.policy,
    poolPolicy: prepared.pool.policy,
    addresses: {
      vault: prepared.vault.address,
      staking: prepared.pool.address,
      config: prepared.vault.source.lockAddress,
    },
    records: f.records,
    rewards,
    finalBacking: core.backingAssets,
    finalSupply: core.economicSupply,
    reusablePosition: marker,
  };
}
