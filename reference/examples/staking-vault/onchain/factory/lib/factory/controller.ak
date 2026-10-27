use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/assets
use cardano/transaction.{Output, OutputReference, Transaction}
use ctvs/ledger
use factory/types.{Instance}

pub type Settings {
  terms: Data,
  binding: Data,
}

type Extension {
  base: Data,
  binding: Data,
}

// Purpose-scoped view only. The existing core independently authenticates the
// complete Config/Terms and immutable binding before economic authorization.
pub type ConfigView {
  magic: ByteArray,
  wire_version: Int,
  vault_policy: ByteArray,
  seed: OutputReference,
  terms_hash: ByteArray,
  terms: Data,
  storage_lovelace: Int,
}

pub fn read_config(out: Output) -> (ConfigView, Data) {
  expect extension: Extension = ledger.raw_datum(out)
  let Pair(tag, fields) = builtin.un_constr_data(extension.base)
  expect tag == 3 && list.length(fields) == 7
  expect config: ConfigView = builtin.constr_data(0, fields)
  (config, extension.binding)
}

pub fn resolve_config(out: Output, instance_hash: ByteArray) -> ConfigView {
  let (config, binding) = read_config(out)
  let settings = Settings { terms: config.terms, binding }
  let instance = Instance {
    version: 1,
    seed: config.seed,
    settings_hash: blake2b_256(builtin.serialise_data(settings)),
  }
  expect instance_hash == blake2b_256(builtin.serialise_data(instance))
  config
}

pub fn referenced_config(tx: Transaction, policy: ByteArray) -> ConfigView {
  expect [input] = list.filter(
    tx.reference_inputs,
    fn(i) { assets.quantity_of(i.output.value, policy, #"4944") != 0 },
  )
  // The core subsequently proves this is the unique locked Config ID created
  // by this controller's one-shot genesis. Its immutable provenance carries
  // the instance check forward; do not require registry permission on exits.
  let (config, _) = read_config(input.output)
  config
}

pub fn hints(out: Output) -> (OutputReference, ByteArray) {
  expect extension: Extension = ledger.raw_datum(out)
  let Pair(tag, fields) = builtin.un_constr_data(extension.base)
  expect tag == 3
  expect [_, _, _, seed_raw, hash_raw, _, _] = fields
  expect seed: OutputReference = seed_raw
  expect terms_hash: ByteArray = hash_raw
  (seed, terms_hash)
}

pub fn referenced_hints(
  tx: Transaction,
  policy: ByteArray,
) -> (OutputReference, ByteArray) {
  expect [input] = list.filter(
    tx.reference_inputs,
    fn(i) { assets.quantity_of(i.output.value, policy, #"4944") != 0 },
  )
  hints(input.output)
}
