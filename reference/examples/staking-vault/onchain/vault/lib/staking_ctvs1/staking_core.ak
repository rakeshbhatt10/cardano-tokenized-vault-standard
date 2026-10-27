use aiken/builtin
// Staking-aware State core. Principal is held by one immutable bound position;
// accrued fees, reward reserves and storage ADA remain physically at State.
// Authentication and accounting invariants shared by the two State handlers.
// Config is referenced, State is consumed, and share minting must match the
// successor's supply delta. Family modules decide which economic action is valid.

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/address.{from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use ctvs/decode
use ctvs/ledger
use ctvs/validation
use ctvs/wire.{
  Config, Datum, MintPurpose, NativeAsset, State, Terms, UpdateSupply,
}
use staking_ctvs1/types.{PoolBinding, StakingConfig}

/// Resolve identity-bearing inputs before trusting their datum fields. The Config
/// must be referenced at its permanent lock and match this script's seed/commitment.
pub fn authenticate(
  tx: Transaction,
  own_ref: OutputReference,
  policy: ByteArray,
  seed: OutputReference,
  commitment: ByteArray,
  lock_hash: ByteArray,
  permits_modes: fn(Int) -> Bool,
) -> (Input, Datum, Terms, PoolBinding) {
  let own = ledger.unique_state(tx, policy)
  expect own.output_reference == own_ref
  expect [config_input] = list.filter(
    tx.reference_inputs,
    fn(i) { assets.quantity_of(i.output.value, policy, wire.id_name) != 0 },
  )
  let (terms, binding) = authenticate_config(
    config_input.output,
    policy,
    seed,
    commitment,
    lock_hash,
    permits_modes,
  )
  expect
    list.all(
      tx.inputs,
      fn(i) { assets.quantity_of(i.output.value, policy, wire.id_name) == 0 },
    )
  let old = decode.state(ledger.raw_datum(own.output))
  expect
    cash_state_output(
      own.output,
      policy,
      commitment,
      old,
      terms.underlying,
      binding,
    )
  (own, old, terms, binding)
}

/// Require the entire mint value to equal this vault's signed share delta.
/// Nonzero deltas need an UpdateSupply redeemer pointing back to the same State;
/// a zero delta requires no mint purposes at all, including unrelated policies.
pub fn supply_mint(
  tx: Transaction,
  policy: ByteArray,
  own_ref: OutputReference,
  delta: Int,
  binding: PoolBinding,
) -> Bool {
  let position = position_name(binding)
  let additional = assets.quantity_of(tx.mint, binding.pool_policy, position)
  expect additional == 0 || additional == 1
  let expected = assets.from_asset(policy, wire.share_name, delta)
    |> assets.add(binding.pool_policy, position, additional)
  expect tx.mint == expected
  // Maintenance with no share delta cannot mint any policy or position identity.
  if delta == 0 {
    expect additional == 0
    list.all(
      tx.redeemers,
      fn(p) {
        when p.1st is {
          transaction.Mint(_) -> False
          _ -> True
        }
      },
    )
  } else {
    let expected: Data = MintPurpose {
      magic: wire.magic,
      wire_version: wire.wire_version,
      action: UpdateSupply { state_ref: own_ref },
    }
    ledger.redeemer(tx, transaction.Mint(policy)) == expected
  }
}

/// Match the action's computed successor to one exact output and its physical value.
/// Exactly one output may carry the permanent State token, and the total mint
/// must equal the economic supply difference from the old State.
/// Bounds on the action's intermediate arithmetic belong to its family handler.
pub fn validate_successor(
  tx: Transaction,
  own_ref: OutputReference,
  policy: ByteArray,
  commitment: ByteArray,
  terms: Terms,
  old: Datum,
  expected: Datum,
  state_output: Int,
  binding: PoolBinding,
) -> Bool {
  expect State { economic_supply: old_supply, .. } = old
  expect  
      State { backing_assets: next_backing, economic_supply: next_supply, .. }
    = expected
  expect
    when terms.max_backing is {
      None -> True
      Some(cap) -> next_backing <= cap
    }
  and {
    cash_state_output(
      ledger.output(tx, state_output),
      policy,
      commitment,
      expected,
      terms.underlying,
      binding,
    ),
    list.length(
      list.filter(
        tx.outputs,
        fn(o) { assets.quantity_of(o.value, policy, wire.state_name) != 0 },
      ),
    ) == 1,
    supply_mint(tx, policy, own_ref, next_supply - old_supply, binding),
  }
}

/// Couple issuance to an authenticated consumed State and its declared successor.
/// This does not recompute the action: the State spending handler must also pass.
pub fn mint_update(
  tx: Transaction,
  state_ref: OutputReference,
  policy: ByteArray,
  successor_index: Int,
) -> Bool {
  expect ledger.allowed_purposes(tx)
  let own = ledger.unique_state(tx, policy)
  expect own.output_reference == state_ref
  let old = decode.state(ledger.raw_datum(own.output))
  expect State { economic_supply: before, .. } = old
  let successor = decode.state(
    ledger.raw_datum(ledger.output(tx, successor_index)),
  )
  expect State { economic_supply: after, .. } = successor
  expect after != before
  // No independent issuance: spending the authenticated State at this same
  // program necessarily executes validate_successor and its full mint checks.
  assets.tokens(tx.mint, policy) == assets.tokens(
    assets.from_asset(policy, wire.share_name, after - before),
    policy,
  )
}

pub fn position_name(binding: PoolBinding) -> ByteArray {
  blake2b_256(builtin.serialise_data(binding.position_seed))
}

pub fn valid_binding(binding: PoolBinding, policy: ByteArray) -> Bool {
  and {
    bytearray.length(binding.pool_policy) == 28,
    binding.pool_policy != policy,
    validation.valid_out_ref(binding.position_seed),
    when binding.reward_asset is {
      NativeAsset { policy_id, asset_name } -> and {
          bytearray.length(policy_id) == 28,
          bytearray.length(asset_name) <= 32,
          policy_id != policy,
          policy_id != binding.pool_policy,
        }
      _ -> False
    },
  }
}

pub fn cash_state_output(
  out: Output,
  policy: ByteArray,
  commitment: ByteArray,
  state: Datum,
  underlying: wire.Asset,
  binding: PoolBinding,
) -> Bool {
  expect State { vault_policy, terms_hash, accrued_fees, storage_lovelace, .. }
    = state
  let raw: Data = state
  expect NativeAsset { policy_id: reward_policy, asset_name: reward_name } = binding.reward_asset
  let rewards = reward_balance(out, binding)
  and {
    validation.q(rewards),
    vault_policy == policy,
    terms_hash == commitment,
    validation.valid_state(state, underlying),
    out.address == from_script(policy),
    out.reference_script == None,
    out.datum == InlineDatum(raw),
    out.value == (
      ledger.economic_value(underlying, accrued_fees, storage_lovelace)
        |> assets.add(policy, wire.state_name, 1)
        |> assets.add(reward_policy, reward_name, rewards)
    ),
  }
}

pub fn reward_balance(out: Output, binding: PoolBinding) -> Int {
  expect NativeAsset { policy_id, asset_name } = binding.reward_asset
  assets.quantity_of(out.value, policy_id, asset_name)
}

// One implementation of immutable Config authentication is shared by genesis
// and State spending. Purpose-scoped Config decoding avoids decoding unrelated
// Request/Claim schemas from the public Datum union.
pub fn authenticate_config(
  output: Output,
  policy: ByteArray,
  seed: OutputReference,
  commitment: ByteArray,
  lock_hash: ByteArray,
  permits_modes: fn(Int) -> Bool,
) -> (Terms, PoolBinding) {
  expect extension: StakingConfig = ledger.raw_datum(output)
  let config = decode.config(extension.base)
  expect valid_binding(extension.binding, policy)
  expect  
      Config {
        vault_policy,
        seed: actual_seed,
        terms_hash,
        terms,
        storage_lovelace,
        ..
      }
    = config
  expect and {
      validation.valid_config(config),
      permits_modes(terms.execution_modes),
      vault_policy == policy,
      actual_seed == seed,
      terms_hash == commitment,
      output.address == from_script(lock_hash),
      output.reference_script == None,
      output.value == (
        assets.from_lovelace(storage_lovelace)
          |> assets.add(policy, wire.id_name, 1)
      ),
      when terms.underlying is {
        NativeAsset { policy_id, .. } -> and {
            policy_id != policy,
            policy_id != extension.binding.pool_policy,
            terms.underlying != extension.binding.reward_asset,
          }
        _ -> False
      },
    }
  (terms, extension.binding)
}
