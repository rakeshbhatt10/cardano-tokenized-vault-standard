import assert from "node:assert/strict";
import { Lucid, type Script, type UTxO } from "@lucid-evolution/lucid";
import type { LocalLedger } from "./ledger.ts";

export async function publishLocalStaking(ledger: LocalLedger, script: Script, funding: UTxO[]) {
  const lucid = await Lucid(ledger.provider, "Preview");

  lucid.selectWallet.fromAddress(ledger.address, funding);

  const completed = await lucid
    .newTx()
    .pay.ToAddressWithData(ledger.address, undefined, { lovelace: 100_000_000n }, script)
    .complete();
  const cbor = completed.toCBOR();
  const estimatedSignedBytes = cbor.length / 2 + 128;

  assert.ok(estimatedSignedBytes <= (await ledger.provider.getProtocolParameters()).maxTxSize);

  return { txId: completed.toHash(), cbor, estimatedSignedBytes };
}
