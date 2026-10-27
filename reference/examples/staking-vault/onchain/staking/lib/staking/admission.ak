// Admission evidence for the immutable factory policy selected at pool creation.
// A valid shape is not provenance: both certificate and Config must carry their
// authentic NFTs. This helper is intentionally separate from State permission.
use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/address
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use staking/registration
use staking/types.{PositionOwner, VaultOwner}

pub type Asset {
  Ada
  NativeAsset { policy_id: PolicyId, asset_name: AssetName }
}

pub type Binding {
  pool_policy: PolicyId,
  position_seed: OutputReference,
  reward_asset: Asset,
}

pub type Extension {
  base: Data,
  binding: Binding,
}

type Config {
  magic: ByteArray,
  wire_version: Int,
  vault_policy: PolicyId,
  seed: OutputReference,
  terms_hash: ByteArray,
  terms: Data,
  storage_lovelace: Int,
}

pub fn validate(
  tx: Transaction,
  factory_policy: PolicyId,
  owner: PositionOwner,
  pool_policy: PolicyId,
  creation_ref: OutputReference,
  principal: Asset,
  reward: Asset,
) -> Bool {
  expect VaultOwner { controller, state_policy, state_name } = owner
  expect builtin.length_of_bytearray(factory_policy) == 28
  expect factory_policy != controller && factory_policy != pool_policy
  // Registration must already exist. Current factory creation deliberately cannot
  // be combined with first position creation using a just-created reference.
  expect assets.quantity_of(tx.mint, factory_policy, controller) == 0
  expect [certificate] = list.filter(
    tx.reference_inputs,
    fn(i) {
      assets.quantity_of(i.output.value, factory_policy, controller) != 0
    },
  )
  expect
    assets.quantity_of(certificate.output.value, factory_policy, controller) == 1
  expect InlineDatum(certificate_raw) = certificate.output.datum
  let proof = registration.decode(certificate_raw)
  expect
    proof.controller == controller && proof.state_policy == state_policy && proof.state_name == state_name
  expect [config_input] = list.filter(
    tx.reference_inputs,
    fn(i) { assets.quantity_of(i.output.value, controller, #"4944") != 0 },
  )
  expect assets.quantity_of(config_input.output.value, controller, #"4944") == 1
  expect InlineDatum(config_raw) = config_input.output.datum
  expect blake2b_256(builtin.serialise_data(config_raw)) == proof.config_hash
  expect address.Script(lock) = certificate.output.address.payment_credential
  expect certificate.output.address == address.from_script(lock)
  expect config_input.output.address == certificate.output.address
  expect extension: Extension = config_raw
  let Pair(config_tag, fields) = builtin.un_constr_data(extension.base)
  expect config_tag == 3 && list.length(fields) == 7
  expect config: Config = builtin.constr_data(0, fields)
  expect
    config.magic == #"43545653" && config.wire_version == 2 && config.vault_policy == controller
  expect
    extension.binding.pool_policy == pool_policy && extension.binding.position_seed == creation_ref && extension.binding.reward_asset == reward
  let Pair(terms_tag, terms_fields) = builtin.un_constr_data(config.terms)
  expect terms_tag == 0 && list.length(terms_fields) == 13
  expect Some(raw_underlying) = list.at(terms_fields, 2)
  expect underlying: Asset = raw_underlying
  expect underlying == principal
  // The configured factory proves the instance commitment when minting this
  // immutable certificate. The exact full-Config hash above binds its economic
  // settings and staking extension; recomputing factory issuance here is redundant.
  // Ledger inputs and reference inputs are disjoint, and these authenticated
  // identities are unique under the factory/controller policies. Their selected
  // reference UTxOs therefore cannot also be consumed in this transaction.
  True
}
