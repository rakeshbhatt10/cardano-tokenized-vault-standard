// Synthetic references test the admission verifier, not factory issuance/creation.
use aiken/builtin
use aiken/crypto.{blake2b_256}
use cardano/address
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use staking/admission.{Binding, Extension, NativeAsset}
use staking/registration.{Registration}
use staking/types.{VaultOwner}

const factory = #"11111111111111111111111111111111111111111111111111111111"

const controller = #"22222222222222222222222222222222222222222222222222222222"

const pool = #"33333333333333333333333333333333333333333333333333333333"

const lock = #"44444444444444444444444444444444444444444444444444444444"

fn ref(index: Int) -> OutputReference {
  OutputReference {
    transaction_id: transaction.placeholder.id,
    output_index: index,
  }
}

fn principal() -> admission.Asset {
  NativeAsset { policy_id: factory, asset_name: #"01" }
}

fn reward() -> admission.Asset {
  NativeAsset { policy_id: factory, asset_name: #"02" }
}

fn binding() -> Binding {
  Binding { pool_policy: pool, position_seed: ref(9), reward_asset: reward() }
}

fn terms() -> Data {
  let asset: Data = principal()
  builtin.constr_data(
    0,
    [
      builtin.i_data(0),
      builtin.b_data(#""),
      asset,
      builtin.i_data(1),
      builtin.constr_data(1, []),
      builtin.i_data(0),
      builtin.i_data(0),
      builtin.constr_data(0, []),
      builtin.constr_data(1, []),
      builtin.constr_data(0, []),
      builtin.i_data(3),
      builtin.i_data(1),
      builtin.constr_data(1, []),
    ],
  )
}

fn config(b: Binding) -> Data {
  let seed: Data = ref(10)
  let base = builtin.constr_data(
    3,
    [
      builtin.b_data(#"43545653"),
      builtin.i_data(2),
      builtin.b_data(controller),
      seed,
      builtin.b_data(blake2b_256(builtin.serialise_data(terms()))),
      terms(),
      builtin.i_data(3_000_000),
    ],
  )
  let result: Data = Extension { base, binding: b }
  result
}

fn proof_for(b: Binding) -> Registration {
  let binding_data: Data = b
  let settings = builtin.constr_data(0, [terms(), binding_data])
  let seed: Data = ref(10)
  let instance = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      seed,
      builtin.b_data(blake2b_256(builtin.serialise_data(settings))),
    ],
  )
  Registration {
    version: 1,
    controller,
    state_policy: controller,
    state_name: #"5354415445",
    implementation: registration.implementation,
    instance_hash: blake2b_256(builtin.serialise_data(instance)),
    config_hash: blake2b_256(builtin.serialise_data(config(b))),
  }
}

fn fixture_with(proof: Registration, b: Binding) -> Transaction {
  let raw: Data = proof
  let certificate = Output {
    address: address.from_script(lock),
    value: assets.from_asset(factory, controller, 1),
    datum: InlineDatum(raw),
    reference_script: None,
  }
  let config_output = Output {
    ..certificate,
    value: assets.from_asset(controller, #"4944", 1),
    datum: InlineDatum(config(b)),
  }
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [
      Input { output_reference: ref(0), output: certificate },
      Input { output_reference: ref(1), output: config_output },
    ],
  }
}

fn fixture() -> Transaction {
  fixture_with(proof_for(binding()), binding())
}

fn validate(tx: Transaction) -> Bool {
  admission.validate(
    tx,
    factory,
    VaultOwner {
      controller,
      state_policy: controller,
      state_name: #"5354415445",
    },
    pool,
    ref(9),
    principal(),
    reward(),
  )
}

test authenticated_reference_profile_matches_config_and_binding() {
  validate(fixture())
}

test certificate_datum_alone_is_not_provenance() fail {
  let tx = fixture()
  expect [certificate, config_input] = tx.reference_inputs
  validate(
    Transaction {
      ..tx,
      reference_inputs: [
        Input {
          ..certificate,
          output: Output {
            ..certificate.output,
            value: assets.from_lovelace(3_000_000),
          },
        },
        config_input,
      ],
    },
  )
}

test self_issued_certificate_policy_rejected() fail {
  let tx = fixture()
  expect [certificate, config_input] = tx.reference_inputs
  validate(
    Transaction {
      ..tx,
      reference_inputs: [
        Input {
          ..certificate,
          output: Output {
            ..certificate.output,
            value: assets.from_asset(lock, controller, 1),
          },
        },
        config_input,
      ],
    },
  )
}

test duplicate_certificate_rejected() fail {
  let tx = fixture()
  expect [certificate, config_input] = tx.reference_inputs
  validate(
    Transaction {
      ..tx,
      reference_inputs: [
        certificate,
        Input { ..certificate, output_reference: ref(2) },
        config_input,
      ],
    },
  )
}

test consumed_certificate_cannot_replace_reference() fail {
  let tx = fixture()
  expect [certificate, config_input] = tx.reference_inputs
  validate(
    Transaction {
      ..tx,
      inputs: [certificate],
      reference_inputs: [config_input],
    },
  )
}

test wrong_full_config_commitment_rejected() fail {
  validate(
    fixture_with(
      Registration {
        ..proof_for(binding()),
        config_hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
      binding(),
    ),
  )
}

test identity_only_probe_rejected() fail {
  validate(
    fixture_with(
      Registration {
        ..proof_for(binding()),
        implementation: #"464143544f52592d4944454e544954592d50524f42452d31",
      },
      binding(),
    ),
  )
}

test malformed_instance_commitment_rejected() fail {
  validate(
    fixture_with(
      Registration { ..proof_for(binding()), instance_hash: #"00" },
      binding(),
    ),
  )
}

test wrong_pool_binding_rejected() fail {
  let b = Binding { ..binding(), pool_policy: lock }
  validate(fixture_with(proof_for(b), b))
}

test wrong_position_seed_rejected() fail {
  let b = Binding { ..binding(), position_seed: ref(8) }
  validate(fixture_with(proof_for(b), b))
}

test wrong_reward_asset_rejected() fail {
  let b = Binding { ..binding(), reward_asset: principal() }
  validate(fixture_with(proof_for(b), b))
}

test wrong_principal_asset_rejected() fail {
  admission.validate(
    fixture(),
    factory,
    VaultOwner {
      controller,
      state_policy: controller,
      state_name: #"5354415445",
    },
    pool,
    ref(9),
    reward(),
    reward(),
  )
}

test config_identity_nft_required() fail {
  let tx = fixture()
  expect [certificate, config_input] = tx.reference_inputs
  validate(
    Transaction {
      ..tx,
      reference_inputs: [
        certificate,
        Input {
          ..config_input,
          output: Output {
            ..config_input.output,
            value: assets.from_lovelace(3_000_000),
          },
        },
      ],
    },
  )
}

test certificate_mint_during_position_open_rejected() fail {
  validate(
    Transaction { ..fixture(), mint: assets.from_asset(factory, controller, 1) },
  )
}
