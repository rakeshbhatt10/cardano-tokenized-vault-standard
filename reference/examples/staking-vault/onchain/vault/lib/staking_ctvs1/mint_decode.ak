use aiken/builtin
use cardano/transaction.{OutputReference}
use ctvs/validation
use ctvs/wire.{Initialize, MintAction, UpdateSupply}

pub fn action(raw: Data) -> MintAction {
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  expect tag == 3
  expect [magic, version, action] = fields
  expect
    magic == builtin.b_data(wire.magic) && version == builtin.i_data(
      wire.wire_version,
    )
  let Pair(kind, payload) = builtin.un_constr_data(action)
  if kind == 0 {
    expect [config, state] = payload
    let c = builtin.un_i_data(config)
    let s = builtin.un_i_data(state)
    expect validation.valid_index(c) && validation.valid_index(s) && c != s
    Initialize { config_output: c, state_output: s }
  } else {
    expect kind == 1
    expect [ref] = payload
    expect state_ref: OutputReference = ref
    expect validation.valid_out_ref(state_ref)
    UpdateSupply { state_ref }
  }
}
