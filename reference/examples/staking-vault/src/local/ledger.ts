/** Synthetic resolved ledger: no keys, signatures, submission or node acceptance. */
import assert from "node:assert/strict";
import {
  CML,
  coreToTxOutput,
  credentialToAddress,
  Emulator,
  type UTxO,
  withCMLScope,
} from "@lucid-evolution/lucid";

export function localLedger() {
  const emulator = new Emulator([]);
  const address = credentialToAddress("Preview", { type: "Key", hash: "12".repeat(28) });
  const provider = new Proxy(emulator, {
    get(target, key) {
      if (key === "submitTx")
        return () => {
          throw Error("Local example never submits");
        };

      const value = Reflect.get(target, key);

      return typeof value === "function" ? value.bind(target) : value;
    },
  });

  const add = (utxo: UTxO) => {
    emulator.ledger[utxo.txHash + utxo.outputIndex] = { utxo: structuredClone(utxo), spent: false };

    return utxo;
  };

  const output = (txHash: string, outputIndex: number) => {
    const entry = emulator.ledger[txHash + outputIndex];

    assert.ok(entry && !entry.spent, "Missing local output");

    return entry.utxo;
  };

  const advance = (cbor: string) =>
    withCMLScope((own) => {
      const transaction = own(CML.Transaction.from_cbor_hex(cbor));

      assert.equal(own(transaction.witness_set()).vkeywitnesses(), undefined);

      const body = own(transaction.body());
      const txHash = own(CML.hash_transaction(body)).to_hex();
      const inputs = own(body.inputs());

      for (let index = 0; index < inputs.len(); index++) {
        const input = own(inputs.get(index));
        const entry = emulator.ledger[own(input.transaction_id()).to_hex() + input.index()];

        assert.ok(entry && !entry.spent);
        entry.spent = true;
      }

      const outputs = own(body.outputs());

      for (let index = 0; index < outputs.len(); index++)
        add({ ...coreToTxOutput(own(outputs.get(index))), txHash, outputIndex: index });

      return txHash;
    });

  return { emulator, provider, address, add, output, advance };
}

export type LocalLedger = ReturnType<typeof localLedger>;

export const outRef = (u: UTxO) => ({ txId: u.txHash, index: BigInt(u.outputIndex) });
