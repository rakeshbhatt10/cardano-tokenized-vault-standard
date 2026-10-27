// Invested single-staking-protocol vault: synchronous native principal entry/exit.
// Config is a local extension of WIRE-2; rewards are unpriced and claimed/distributed on exit.
// CTVS-1 uses one parameterized program for State spending and share minting.
// The spend handler proves the economic transition; minting cross-checks the
// same consumed State so issuance cannot be authorized independently.

use aiken/primitive/bytearray
use cardano/address.{Script, from_script}
use cardano/assets
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use ctvs/deployment
use ctvs/ledger
use ctvs/wire.{Initialize, UpdateSupply}
use factory/controller
use factory/genesis
use staking_ctvs1/mint_decode
use staking_ctvs1/staking_state as state

/// Independent family entrypoint. Permanent identity assets select State
/// dispatch before any untrusted datum or redeemer can select a user action.
validator vault(instance_hash: ByteArray) {
  spend(
    supplied: Option<Data>,
    raw_redeemer: Data,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect bytearray.length(deployment.config_lock_hash) == 28
    let own = ledger.input(tx, own_ref)
    expect Script(policy) = own.output.address.payment_credential
    let (seed, commitment) = controller.referenced_hints(tx, policy)
    expect
      own.output.address == from_script(policy) && own.output.reference_script == None
    expect assets.quantity_of(own.output.value, policy, wire.id_name) == 0
    expect InlineDatum(raw) = own.output.datum
    expect supplied == Some(raw)
    let state_quantity = assets.quantity_of(
      own.output.value,
      policy,
      wire.state_name,
    )
    expect state_quantity == 1
    let (action, max_reward_input, min_reward_output) = state.decode_action(
      raw_redeemer,
    )
    state.validate(
      tx,
      own_ref,
      policy,
      seed,
      commitment,
      deployment.config_lock_hash,
      action,
      max_reward_input,
      min_reward_output,
    )
  }

  mint(raw_redeemer: Data, policy: ByteArray, tx: Transaction) {
    expect bytearray.length(deployment.config_lock_hash) == 28
    let action = mint_decode.action(raw_redeemer)
    when action is {
      Initialize { config_output, state_output } -> {
        let (seed, commitment) = controller.hints(
          ledger.output(tx, config_output),
        )
        genesis.validate(
          tx,
          policy,
          seed,
          commitment,
          deployment.config_lock_hash,
          config_output,
          state_output,
          state.permits_modes,
          instance_hash,
        )
      }
      UpdateSupply { state_ref } -> {
        // The genuine State must be consumed at this same program. Its spend
        // handler checks the complete envelope, economic transition, continuation
        // and exact transaction-wide mint, including this UpdateSupply reference.
        let own = ledger.unique_state(tx, policy)
        own.output_reference == state_ref
      }
    }
  }

  else(_) {
    fail
  }
}
