import { CML, fromCMLRedeemerTag, withCMLScope, type EvalRedeemer, type EvaluationInput } from '@lucid-evolution/lucid';

/** Check final unsigned witness budgets and exact purpose coverage against fresh measured costs. */
export function checkFinalBudgets(cbor: string, evaluated: EvalRedeemer[], context: EvaluationInput['context']) {
  return withCMLScope(own => {
    const tx = own(CML.Transaction.from_cbor_hex(cbor));
    const witnesses = own(tx.witness_set());
    const optional = witnesses.redeemers();
    const budgets = new Map<string, { mem: bigint; steps: bigint }>();
    if (optional) {
      const flat = own(own(optional).to_flat_format());
      for (let i = 0; i < flat.len(); i++) {
        const r = own(flat.get(i)); const units = own(r.ex_units());
        const key = `${fromCMLRedeemerTag(r.tag())}:${r.index()}`;
        if (budgets.has(key)) throw new Error('Duplicate declared redeemer');
        budgets.set(key, { mem: units.mem(), steps: units.steps() });
      }
    }
    const seen = new Set<string>();
    for (const r of evaluated) {
      if (!Number.isSafeInteger(r.redeemer_index) || r.redeemer_index < 0 || !Number.isSafeInteger(r.ex_units.mem) || r.ex_units.mem < 0 || !Number.isSafeInteger(r.ex_units.steps) || r.ex_units.steps < 0) throw new Error('Invalid measured execution units');
      const key = `${r.redeemer_tag}:${r.redeemer_index}`;
      if (seen.has(key)) throw new Error('Duplicate evaluated redeemer');
      seen.add(key);
      const budget = budgets.get(key);
      if (!budget || budget.mem < BigInt(r.ex_units.mem) || budget.steps < BigInt(r.ex_units.steps)) throw new Error('Final redeemer budget or coverage mismatch');
    }
    if (seen.size !== budgets.size) throw new Error('Final redeemer coverage incomplete');
    const total = [...budgets.values()].reduce((a, b) => ({ mem: a.mem + b.mem, steps: a.steps + b.steps }), { mem: 0n, steps: 0n });
    if (total.mem > context.protocolParameters.maxTxExMem || total.steps > context.protocolParameters.maxTxExSteps) throw new Error('Final aggregate execution budget exceeds limits');
    if (cbor.length / 2 > context.protocolParameters.maxTxSize) throw new Error('Final transaction exceeds size limit');
    return { redeemers: evaluated, bytes: cbor.length / 2, declared: { memory: total.mem.toString(), steps: total.steps.toString() }, limits: { memory: context.protocolParameters.maxTxExMem.toString(), steps: context.protocolParameters.maxTxExSteps.toString(), bytes: context.protocolParameters.maxTxSize } };
  });
}
