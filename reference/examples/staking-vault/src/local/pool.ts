import assert from "node:assert/strict";
import {
  Constr,
  Data,
  type EvaluationInput,
  Lucid,
  SLOT_CONFIG_NETWORK,
  type UTxO,
} from "@lucid-evolution/lucid";
import { RecordedEvaluator } from "../../../../testing/ledger/evaluator.ts";
import { decodePoolDatum, encodePoolDatum } from "../../vendor/client/src/staking/datum.ts";
import { checkFinalBudgets } from "../../vendor/client/support/evaluation.ts";
import type { prepareFactoryDeployment } from "../index.ts";
import { inspectPoolTransaction } from "./inspection.ts";
import type { LocalLedger } from "./ledger.ts";

type Prepared = ReturnType<typeof prepareFactoryDeployment>;

/** Pool initialization / reward notification is separate from per-vault creation.
 * This helper is only for fabricated local UTxOs and address-only construction. */
export async function poolTransaction(
  ledger: LocalLedger,
  prepared: Prepared,
  funding: UTxO[],
  collateral: UTxO,
  reference: UTxO,
  time?: bigint,
) {
  const evaluator = new RecordedEvaluator();
  let captured: EvaluationInput | undefined;
  const lucid = await Lucid(ledger.provider, "Preview", {
    slotConfig: SLOT_CONFIG_NETWORK.Preview,
    evaluator: {
      evaluate: async (input) => {
        captured = input;

        return evaluator.evaluate(input);
      },
    },
  });

  lucid.selectWallet.fromAddress(ledger.address, [collateral]);

  const { pool } = prepared;
  let builder = lucid
    .newTx()
    .collectFrom(funding)
    .readFrom([reference])
    .addSignerKey(pool.settings.manager);

  if (time === undefined) {
    builder = builder
      .mintAssets({ [pool.poolUnit]: 1n }, Data.to(new Constr(0, [])))
      .pay.ToAddressWithData(
        pool.address,
        { kind: "inline", value: pool.initialDatum },
        { lovelace: 5_000_000n, [pool.poolUnit]: 1n },
      );
  } else {
    const previous = await ledger.provider.getUtxoByUnit(pool.poolUnit);

    assert.ok(previous.datum);

    const state = decodePoolDatum(previous.datum);

    assert.equal(state.rewardRate, 0n);

    const reward = pool.settings.rewardAsset.policyId + pool.settings.rewardAsset.tokenNameHex;
    const amount = 6_048_000n;
    const datum = encodePoolDatum({
      ...state,
      rewardDurationSeconds: 604800n,
      periodFinishSeconds: time / 1000n + 604800n,
      rewardRate: 10n,
      lastUpdateSeconds: time / 1000n,
    });

    builder = builder
      .collectFrom([previous], Data.to(new Constr(5, [amount, 604800n])))
      .pay.ToAddressWithData(
        pool.address,
        { kind: "inline", value: datum },
        { ...previous.assets, [reward]: (previous.assets[reward] ?? 0n) + amount },
      )
      .validFrom(Number(time))
      .validTo(Number(time + 60000n));
  }

  const completed = await builder.complete({ setCollateral: 2_000_000n });
  const cbor = completed.toCBOR();

  assert.ok(captured);

  const measured = await evaluator.evaluate({ ...captured, tx: cbor });
  const finalEvaluation = checkFinalBudgets(cbor, measured, captured.context);
  const inspected = inspectPoolTransaction(cbor, await ledger.provider.getProtocolParameters());

  return {
    txId: completed.toHash(),
    cbor,
    finalEvaluation,
    ...inspected,
    signed: false,
    submitted: false,
  };
}
