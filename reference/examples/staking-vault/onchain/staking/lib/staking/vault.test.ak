use aiken/builtin
use cardano/address
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction,
}
use staking/authorization.{Operation, Stake, WithdrawAndClaim}
use staking/types.{PositionOwner, VaultOwner, WalletOwner}
use staking/vault.{validate_exit_evidence, validate_stake_evidence}

type Intent {
  version: Int,
  pool_id: ByteArray,
  position_name: ByteArray,
  operation: Operation,
  amount: Int,
  creation_ref: Option<OutputReference>,
  state_output: Int,
  base: Data,
  max_reward_input: Int,
  min_reward_output: Int,
}

const controller = #"11111111111111111111111111111111111111111111111111111111"

const pool_id = #"22222222222222222222222222222222222222222222222222222222"

const position_name =
  #"3333333333333333333333333333333333333333333333333333333333333333"

const state_name = #"5354415445"

fn ref(index: Int) -> OutputReference {
  OutputReference {
    transaction_id: transaction.placeholder.id,
    output_index: index,
  }
}

fn owner() -> PositionOwner {
  VaultOwner { controller, state_policy: controller, state_name }
}

fn intent() -> Intent {
  Intent {
    version: 1,
    operation: Stake,
    pool_id,
    position_name,
    amount: 50,
    creation_ref: Some(ref(9)),
    state_output: 0,
    base: base_action(0),
    max_reward_input: 0,
    min_reward_output: 0,
  }
}

fn state_output() -> Output {
  Output {
    address: address.from_script(controller),
    value: assets.from_lovelace(2_000_000)
      |> assets.add(controller, state_name, 1),
    datum: InlineDatum(builtin.i_data(0)),
    reference_script: None,
  }
}

fn staking_output(name: ByteArray) -> Output {
  Output {
    ..state_output(),
    address: address.from_script(pool_id),
    value: assets.from_asset(pool_id, name, 1),
  }
}

fn fixture_for(intent: Intent) -> Transaction {
  let raw: Data = intent
  let action = authorization.staking_action(authorization.decode(raw))
  let pool_input = Input {
    output_reference: ref(1),
    output: staking_output(#"504f4f4c"),
  }
  let state_input = Input { output_reference: ref(0), output: state_output() }
  let inputs = when intent.creation_ref is {
    Some(seed) ->
      [
        state_input,
        pool_input,
        Input {
          output_reference: seed,
          output: Output {
            ..state_output(),
            address: address.from_verification_key(controller),
            value: assets.from_lovelace(3_000_000),
          },
        },
      ]
    None ->
      [
        state_input,
        pool_input,
        Input {
          output_reference: ref(2),
          output: staking_output(position_name),
        },
      ]
  }
  let redeemers = [Pair(Spend(ref(0)), raw), Pair(Spend(ref(1)), action)]
  Transaction {
    ..transaction.placeholder,
    inputs,
    outputs: [
      state_output(),
      staking_output(#"504f4f4c"),
      staking_output(position_name),
    ],
    mint: if intent.creation_ref == None {
      assets.zero
    } else {
      assets.from_asset(pool_id, position_name, 1)
    },
    redeemers: if intent.creation_ref == None {
      [Pair(Spend(ref(2)), action), ..redeemers]
    } else {
      redeemers
    },
  }
}

fn fixture() -> Transaction {
  fixture_for(intent())
}

fn validate(tx: Transaction) -> Bool {
  validate_stake_evidence(
    tx,
    owner(),
    address.from_script(controller),
    pool_id,
    position_name,
    50,
    Some(ref(9)),
  )
}

fn with_intent(authorization: Intent) -> Transaction {
  fixture_for(authorization)
}

test state_evidence_requires_no_wallet_signature() {
  validate(fixture())
}

test share_mint_is_distinct_from_state_mint() {
  validate(
    Transaction {
      ..fixture(),
      mint: fixture().mint |> assets.add(controller, #"5348415245", 10),
    },
  )
}

test state_reference_is_not_a_consumed_state() fail {
  let tx = fixture()
  validate(Transaction { ..tx, inputs: [], reference_inputs: tx.inputs })
}

test duplicate_state_inputs_rejected() fail {
  let input = Input { output_reference: ref(1), output: state_output() }
  validate(Transaction { ..fixture(), inputs: [input, ..fixture().inputs] })
}

test wrong_controller_address_rejected() fail {
  let output = Output {
    ..state_output(),
    address: address.from_script(pool_id),
  }
  validate(
    Transaction {
      ..fixture(),
      inputs: [Input { output_reference: ref(0), output }],
    },
  )
}

test wrong_state_asset_rejected() fail {
  let output = Output {
    ..state_output(),
    value: assets.from_asset(controller, #"46414b45", 1),
  }
  validate(
    Transaction {
      ..fixture(),
      inputs: [Input { output_reference: ref(0), output }],
    },
  )
}

test duplicate_state_quantity_rejected() fail {
  let output = Output {
    ..state_output(),
    value: assets.from_asset(controller, state_name, 2),
  }
  validate(
    Transaction {
      ..fixture(),
      inputs: [Input { output_reference: ref(0), output }],
    },
  )
}

test state_mint_rejected() fail {
  validate(
    Transaction {
      ..fixture(),
      mint: assets.from_asset(controller, state_name, 1),
    },
  )
}

test state_burn_rejected() fail {
  validate(
    Transaction {
      ..fixture(),
      mint: assets.from_asset(controller, state_name, -1),
    },
  )
}

test wallet_signature_cannot_replace_controller_action() fail {
  validate(
    Transaction { ..fixture(), redeemers: [], extra_signatories: [controller] },
  )
}

test mismatched_pool_rejected() fail {
  validate(with_intent(Intent { ..intent(), pool_id: controller }))
}

test mismatched_position_rejected() fail {
  validate(with_intent(Intent { ..intent(), position_name: #"00" }))
}

test mismatched_amount_rejected() fail {
  validate(with_intent(Intent { ..intent(), amount: 51 }))
}

test mismatched_creation_ref_rejected() fail {
  validate(with_intent(Intent { ..intent(), creation_ref: None }))
}

test unsupported_intent_version_rejected() fail {
  let raw: Data = Intent { ..intent(), version: 2 }
  validate(Transaction { ..fixture(), redeemers: [Pair(Spend(ref(0)), raw)] })
}

test missing_continuation_rejected() fail {
  validate(Transaction { ..fixture(), outputs: [] })
}

test duplicate_continuations_rejected() fail {
  validate(
    Transaction { ..fixture(), outputs: [state_output(), state_output()] },
  )
}

test redirected_continuation_rejected() fail {
  validate(
    Transaction {
      ..fixture(),
      outputs: [
        Output { ..state_output(), address: address.from_script(pool_id) },
      ],
    },
  )
}

test incorrect_output_index_rejected() fail {
  validate(with_intent(Intent { ..intent(), state_output: 1 }))
}

test wallet_owner_is_not_vault_evidence() fail {
  validate_stake_evidence(
    fixture(),
    WalletOwner(controller),
    address.from_script(controller),
    pool_id,
    position_name,
    50,
    Some(ref(9)),
  )
}

test redirected_custody_address_rejected() fail {
  validate_stake_evidence(
    fixture(),
    owner(),
    address.from_verification_key(controller),
    pool_id,
    position_name,
    50,
    Some(ref(9)),
  )
}

fn base_action(tag: Int) -> Data {
  let receiver = builtin.constr_data(
    0,
    [
      builtin.constr_data(
        0,
        [
          builtin.constr_data(0, [builtin.b_data(controller)]),
          builtin.constr_data(1, []),
        ],
      ),
      builtin.constr_data(1, []),
    ],
  )
  builtin.constr_data(
    0,
    [
      builtin.b_data(#"43545653"),
      builtin.i_data(2),
      builtin.constr_data(
        tag,
        [
          receiver,
          builtin.i_data(50),
          builtin.i_data(100),
          builtin.i_data(0),
          builtin.i_data(1),
        ],
      ),
    ],
  )
}

test exit_evidence_uses_shared_envelope() {
  let exit = Intent {
    version: 1,
    pool_id,
    position_name,
    operation: WithdrawAndClaim,
    amount: 50,
    creation_ref: None,
    state_output: 0,
    base: base_action(2),
    max_reward_input: 0,
    min_reward_output: 1,
  }
  validate_exit_evidence(
    with_intent(exit),
    owner(),
    address.from_script(controller),
    pool_id,
    position_name,
    50,
  )
}

test entry_cannot_authorize_exit() fail {
  validate_exit_evidence(
    fixture(),
    owner(),
    address.from_script(controller),
    pool_id,
    position_name,
    50,
  )
}

test missing_pool_spend_rejected() fail {
  expect [state, _, seed] = fixture().inputs
  validate(Transaction { ..fixture(), inputs: [state, seed] })
}

test mismatched_actual_pool_action_rejected() fail {
  let raw: Data = intent()
  let wrong = builtin.constr_data(
    0,
    [
      builtin.i_data(51),
      builtin.b_data(position_name),
      builtin.constr_data(1, []),
    ],
  )
  validate(
    Transaction {
      ..fixture(),
      redeemers: [Pair(Spend(ref(0)), raw), Pair(Spend(ref(1)), wrong)],
    },
  )
}

test extra_staking_position_mint_rejected() fail {
  validate(
    Transaction {
      ..fixture(),
      mint: fixture().mint |> assets.add(pool_id, #"6578747261", 1),
    },
  )
}

test second_position_input_rejected() fail {
  let tx = fixture_for(Intent { ..intent(), creation_ref: None })
  validate_stake_evidence(
    Transaction {
      ..tx,
      inputs: [
        Input {
          output_reference: ref(3),
          output: staking_output(#"6578747261"),
        },
        ..tx.inputs
      ],
    },
    owner(),
    address.from_script(controller),
    pool_id,
    position_name,
    50,
    None,
  )
}

test topup_with_exact_pool_and_position_actions_succeeds() {
  validate_stake_evidence(
    fixture_for(Intent { ..intent(), creation_ref: None }),
    owner(),
    address.from_script(controller),
    pool_id,
    position_name,
    50,
    None,
  )
}

test missing_creation_seed_rejected() fail {
  expect [state, pool, _] = fixture().inputs
  validate(Transaction { ..fixture(), inputs: [state, pool] })
}
