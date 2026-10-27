import assert from "node:assert/strict";
import { CML, type ProtocolParameters, withCMLScope } from "@lucid-evolution/lucid";

/** Phase-one bounds inspected locally; signatures and node acceptance are still absent. */
export function inspectPoolTransaction(cbor: string, parameters: ProtocolParameters) {
  return withCMLScope((own) => {
    const transaction = own(CML.Transaction.from_cbor_hex(cbor));
    const body = own(transaction.body());
    const fee = body.fee();
    const exposure = body.total_collateral();
    const required = (fee * BigInt(parameters.collateralPercentage) + 99n) / 100n;

    assert.ok(fee <= 3_000_000n);
    assert.ok(exposure !== undefined && exposure >= required && exposure <= 5_000_000n);

    const outputs = own(body.outputs());
    const minimumAda = [];

    for (let index = 0; index < outputs.len(); index++) {
      const output = own(outputs.get(index));
      const actual = own(output.amount()).coin();
      const minimum = CML.min_ada_required(output, parameters.coinsPerUtxoByte);

      assert.ok(actual >= minimum);
      minimumAda.push({ index, actualLovelace: String(actual), minimumLovelace: String(minimum) });
    }

    const collateralReturn = body.collateral_return();

    if (collateralReturn) {
      const output = own(collateralReturn);

      assert.ok(
        own(output.amount()).coin() >= CML.min_ada_required(output, parameters.coinsPerUtxoByte),
      );
    }

    // Local funding, collateral and manager/distributor all use the same fabricated key hash.
    const estimatedSignedBytes = cbor.length / 2 + 128;

    assert.ok(estimatedSignedBytes <= parameters.maxTxSize);

    return {
      feeLovelace: String(fee),
      estimatedSignedBytes,
      minimumAda,
      collateralCheck: { requiredLovelace: String(required), exposureLovelace: String(exposure) },
    };
  });
}
