use aiken/builtin
use aiken/collection/dict
// Automatic instance-committed pool binding, frozen at Config lock before deposits.
// One-shot creation of Config and State identities, anchored to a consumed seed.
// Shared genesis checks authenticate Terms and empty initial accounting; the
// family supplies its own permitted execution modes.

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/assets
use cardano/transaction.{OutputReference, Transaction}
use ctvs/decode
use ctvs/ledger
use ctvs/validation
use ctvs/wire.{State}
use factory/controller.{Settings}
use factory/types.{Instance}
use staking_ctvs1/staking_core

/// Mint exactly the permanent identities from key-controlled inputs. Consuming
/// the seed makes initialization one-shot; initial economic share supply is zero.
pub fn validate(
  tx: Transaction,
  policy: ByteArray,
  seed: OutputReference,
  commitment: ByteArray,
  lock_hash: ByteArray,
  config_index: Int,
  state_index: Int,
  permits_modes: fn(Int) -> Bool,
  instance_hash: ByteArray,
) -> Bool {
  // The independently executing factory authenticates certificate issuance and
  // its exact locked output. This controller enforces its own genesis plus the
  // narrowly allowed single certificate mint; no factory hash recursion.
  expect [Pair(certificate_policy, _)] = tx.mint
    |> assets.to_dict
    |> dict.to_pairs
    |> list.filter(fn(p) { p.1st != policy })
  expect and {
      ledger.allowed_purposes(tx),
      config_index != state_index,
      validation.valid_out_ref(seed),
      list.all(tx.inputs, ledger.key_input),
      list.any(tx.inputs, fn(i) { i.output_reference == seed }),
      tx.mint == (
        assets.from_asset(policy, wire.id_name, 1)
          |> assets.add(policy, wire.state_name, 1)
          |> assets.add(certificate_policy, policy, 1)
      ),
    }
  let config_out = ledger.output(tx, config_index)
  let (terms, binding) = staking_core.authenticate_config(
    config_out,
    policy,
    seed,
    commitment,
    lock_hash,
    permits_modes,
  )
  let raw_terms: Data = terms
  let raw_binding: Data = binding
  let settings = Settings { terms: raw_terms, binding: raw_binding }
  let instance = Instance {
    version: 1,
    seed,
    settings_hash: blake2b_256(builtin.serialise_data(settings)),
  }
  expect instance_hash == blake2b_256(builtin.serialise_data(instance))
  let state_out = ledger.output(tx, state_index)
  let state = decode.state(ledger.raw_datum(state_out))
  expect  
      State {
        sequence,
        backing_assets,
        economic_supply,
        accrued_fees,
        pause_flags,
        ..
      }
    = state
  and {
    staking_core.reward_balance(state_out, binding) == 0,
    sequence == 0,
    backing_assets == 0,
    economic_supply == 0,
    accrued_fees == 0,
    pause_flags == 0,
    staking_core.cash_state_output(
      state_out,
      policy,
      commitment,
      state,
      terms.underlying,
      binding,
    ),
    list.length(
      list.filter(
        tx.outputs,
        fn(o) { assets.quantity_of(o.value, policy, wire.state_name) != 0 },
      ),
    ) == 1,
    list.length(
      list.filter(
        tx.outputs,
        fn(o) { assets.quantity_of(o.value, policy, wire.id_name) != 0 },
      ),
    ) == 1,
    list.all(
      tx.inputs,
      fn(i) {
        assets.quantity_of(i.output.value, policy, wire.id_name) == 0 && assets.quantity_of(
          i.output.value,
          policy,
          wire.state_name,
        ) == 0
      },
    ),
  }
}
