import assert from "node:assert/strict";
import { Data, type UTxO } from "@lucid-evolution/lucid";
import {
  constructFactoryPublication,
  prepareFactoryPublication,
} from "../../vendor/client/src/factory/publication.ts";
import { constructFactoryVaultGenesis, constructFactoryVaultPublication } from "../index.ts";
import { type LocalLedger, localLedger, outRef } from "./ledger.ts";
import { poolTransaction } from "./pool.ts";
import { publishLocalStaking } from "./publication.ts";
import { localSettings } from "./settings.ts";

function seededLocalLedger() {
  const ledger = localLedger();
  const prepared = localSettings(ledger);
  const { vault, pool } = prepared;

  const addCash = (hash: string, lovelace: bigint) =>
    ledger.add({
      txHash: hash.repeat(32),
      outputIndex: 0,
      address: ledger.address,
      assets: { lovelace },
    });

  const collateral = addCash("ae", 5_000_000n);
  const poolSeed = addCash("ab", 30_000_000n);
  const vaultSeed = addCash("ac", 30_000_000n);
  const positionSeed = addCash("ad", 5_000_000n);

  addCash("aa", 3_000_000_000n);

  const principal = pool.settings.stakingAsset.policyId + pool.settings.stakingAsset.tokenNameHex;
  const reward = pool.settings.rewardAsset.policyId + pool.settings.rewardAsset.tokenNameHex;
  const tokens = ledger.add({
    txHash: "af".repeat(32),
    outputIndex: 0,
    address: ledger.address,
    assets: { lovelace: 500_000_000n, [principal]: 1_000_000_000n, [reward]: 1_000_000_000n },
  });
  const protectedInputs = [poolSeed, vaultSeed, positionSeed, collateral, tokens].map(outRef);

  return {
    ledger,
    prepared,
    vault,
    pool,
    collateral,
    poolSeed,
    vaultSeed,
    positionSeed,
    tokens,
    principal,
    reward,
    protectedInputs,
  };
}

export async function setupLocalExample() {
  const {
    ledger,
    prepared,
    vault,
    pool,
    collateral,
    poolSeed,
    vaultSeed,
    tokens,
    principal,
    reward,
    protectedInputs,
  } = seededLocalLedger();
  const publication = prepareFactoryPublication({
    schema: "STAKING-CTVS1-FACTORY-PUBLICATION-SETTINGS-1",
    network: "Preview",
    fundingAddress: ledger.address,
    reserves: { factory: "100000000", prefix0: "100000000", prefix1: "100000000" },
    maxNetworkFeeLovelace: "3000000",
    protectedInputs: protectedInputs.map((r) => ({ txId: r.txId, index: String(r.index) })),
  });
  const records: {
    stage: string;
    txId: string;
    cbor: string;
    estimatedSignedBytes: number;
    finalEvaluation?: unknown;
  }[] = [];
  const references: UTxO[] = [];

  for (const stage of ["factory", "prefix0", "prefix1"] as const) {
    const tx = await constructFactoryPublication(publication, stage, ledger.provider);

    ledger.advance(tx.cbor);
    references.push(ledger.output(tx.txId, 0));
    records.push({ ...tx, stage: `publish-${stage}` });
  }

  const reserved = new Set(protectedInputs.map((r) => `${r.txId}#${r.index}`));

  const cleanFunding = async () =>
    (await ledger.provider.getUtxos(ledger.address)).filter(
      (u) =>
        !u.scriptRef &&
        !u.datum &&
        Object.keys(u.assets).length === 1 &&
        !reserved.has(`${u.txHash}#${u.outputIndex}`),
    );

  const common = creationLimits(ledger);
  const controllerTx = await constructFactoryVaultPublication(vault, 100_000_000n, {
    ...common,
    funding: await cleanFunding(),
    collateral: [],
  });

  ledger.advance(controllerTx.cbor);
  records.push({ stage: "publish-controller", ...controllerTx });

  const controller = ledger.output(controllerTx.txId, 0);
  const [factory, prefix0, prefix1] = references;

  assert.ok(factory && prefix0 && prefix1);

  const genesis = await constructFactoryVaultGenesis(
    vault,
    vaultSeed,
    { factory, prefix0, prefix1, controller },
    4_000_000n,
    { ...common, funding: [...(await cleanFunding()), vaultSeed], collateral: [collateral] },
  );

  ledger.advance(genesis.cbor);
  records.push({ stage: "vault-genesis-and-registration", ...genesis });

  const stakingPublication = await publishLocalStaking(ledger, pool.script, await cleanFunding());

  ledger.advance(stakingPublication.cbor);
  records.push({ stage: "publish-staking", ...stakingPublication });

  const staking = ledger.output(stakingPublication.txId, 0);
  const poolGenesis = await poolTransaction(
    ledger,
    prepared,
    [...(await cleanFunding()), poolSeed],
    collateral,
    staking,
  );

  ledger.advance(poolGenesis.cbor);
  records.push({ stage: "pool-genesis", ...poolGenesis });

  const time = 1_793_100_000_000n;
  const notify = await poolTransaction(ledger, prepared, [tokens], collateral, staking, time);

  ledger.advance(notify.cbor);
  records.push({ stage: "notify-rewards", ...notify });
  assert.equal(Data.to(vault.stateData), ledger.output(genesis.txId, 1).datum);

  return {
    ledger,
    prepared,
    records,
    principal,
    reward,
    collateral,
    time,
    controller,
    staking,
    config: ledger.output(genesis.txId, 0),
    certificate: ledger.output(genesis.txId, 2),
  };
}

function creationLimits(ledger: LocalLedger) {
  return {
    provider: ledger.provider,
    fundingAddress: ledger.address,
    protectedInputs: [],
    maxNetworkFee: 3_000_000n,
    maxCollateralExposure: 5_000_000n,
  };
}
