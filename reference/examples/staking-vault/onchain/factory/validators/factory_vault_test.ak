// Mint-purpose boundary tests. Successful supply transitions additionally require
// the independently evaluated State spending purpose in the same transaction.
use aiken/builtin
use cardano/address.{from_script}
use cardano/assets
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use factory_vault

const policy = #"11111111111111111111111111111111111111111111111111111111"

fn ref(index: Int) -> OutputReference {
  OutputReference {
    transaction_id: transaction.placeholder.id,
    output_index: index,
  }
}

fn input() -> Input {
  Input {
    output_reference: ref(0),
    output: Output {
      address: from_script(policy),
      value: assets.from_asset(policy, #"5354415445", 1),
      datum: transaction.NoDatum,
      reference_script: None,
    },
  }
}

fn envelope() -> Data {
  builtin.constr_data(
    3,
    [
      builtin.b_data(#"43545653"),
      builtin.i_data(2),
      builtin.constr_data(
        1,
        [
          builtin.constr_data(
            0,
            [builtin.b_data(transaction.placeholder.id), builtin.i_data(0)],
          ),
        ],
      ),
    ],
  )
}

fn check(tx: Transaction) -> Bool {
  factory_vault.vault.mint(
    #"0000000000000000000000000000000000000000000000000000000000000000",
    envelope(),
    policy,
    tx,
  )
}

test no_consumed_state_rejected() fail {
  check(transaction.placeholder)
}

test reference_only_state_rejected() fail {
  check(Transaction { ..transaction.placeholder, reference_inputs: [input()] })
}

test duplicate_state_rejected() fail {
  let first = input()
  check(
    Transaction {
      ..transaction.placeholder,
      inputs: [first, Input { ..first, output_reference: ref(1) }],
    },
  )
}

test wrong_state_reference_rejected() fail {
  let first = input()
  check(
    Transaction {
      ..transaction.placeholder,
      inputs: [Input { ..first, output_reference: ref(1) }],
    },
  )
}

test wrong_state_address_rejected() fail {
  let first = input()
  check(
    Transaction {
      ..transaction.placeholder,
      inputs: [
        Input {
          ..first,
          output: Output {
            ..first.output,
            address: from_script(
              #"22222222222222222222222222222222222222222222222222222222",
            ),
          },
        },
      ],
    },
  )
}

test wrong_state_quantity_rejected() fail {
  let first = input()
  check(
    Transaction {
      ..transaction.placeholder,
      inputs: [
        Input {
          ..first,
          output: Output {
            ..first.output,
            value: assets.from_asset(policy, #"5354415445", 2),
          },
        },
      ],
    },
  )
}

test extra_mint_envelope_field_rejected() fail {
  let Pair(tag, fields) = builtin.un_constr_data(envelope())
  factory_vault.vault.mint(
    #"0000000000000000000000000000000000000000000000000000000000000000",
    builtin.constr_data(tag, [builtin.i_data(0), ..fields]),
    policy,
    transaction.placeholder,
  )
}
