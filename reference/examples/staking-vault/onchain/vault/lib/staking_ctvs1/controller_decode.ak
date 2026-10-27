// Shared v1 wire checked once without constructing the outer Authorization record.
use aiken/builtin
use aiken/collection/list
use aiken/primitive/bytearray
use ctvs/validation
use ctvs/wire.{StateAction}
use staking_ctvs1/controller_action as staking_decode

fn base_fields(raw: Data) -> Pair<Int, List<Data>> {
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  expect tag == 0
  expect [_, _, action] = fields
  builtin.un_constr_data(action)
}

pub fn decode(raw: Data) -> (StateAction, Int, Int) {
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  if tag == 1 {
    expect [version, base] = fields
    expect builtin.un_i_data(version) == 1
    let action = staking_decode.action(base)
    let Pair(kind, _) = base_fields(base)
    expect kind >= 5 && kind <= 7
    (action, 0, 0)
  } else {
    expect tag == 0
    expect  
        [
          version, pool, name, operation, amount, creation, state_output, base,
          max_reward_input, min_reward_output,
        ]
      = fields
    expect
      builtin.un_i_data(version) == 1 && bytearray.length(
        builtin.un_b_data(pool),
      ) == 28 && bytearray.length(builtin.un_b_data(name)) == 32
    let principal = builtin.un_i_data(amount)
    let successor = builtin.un_i_data(state_output)
    let max_reward = builtin.un_i_data(max_reward_input)
    let min_reward = builtin.un_i_data(min_reward_output)
    expect
      validation.positive_q(principal) && validation.valid_index(successor) && validation.q(
        max_reward,
      ) && validation.q(min_reward)
    let Pair(op, op_fields) = builtin.un_constr_data(operation)
    expect ( op == 0 || op == 1 ) && list.is_empty(op_fields)
    let Pair(mode, mode_fields) = builtin.un_constr_data(creation)
    expect
      if mode == 0 {
        expect [raw_ref] = mode_fields
        let Pair(ref_tag, ref_fields) = builtin.un_constr_data(raw_ref)
        expect ref_tag == 0
        expect [tx_id, index] = ref_fields
        bytearray.length(builtin.un_b_data(tx_id)) == 32 && validation.valid_index(
          builtin.un_i_data(index),
        )
      } else {
        mode == 1 && list.is_empty(mode_fields)
      }
    let action = staking_decode.action(base)
    let Pair(kind, payload) = base_fields(base)
    expect kind >= 0 && kind <= 3
    expect [_, _, _, inner_successor, _] = payload
    expect state_output == inner_successor
    let entering = kind <= 1
    expect
      if entering {
        op == 0 && min_reward == 0
      } else {
        op == 1 && mode == 1 && max_reward == 0
      }
    (action, max_reward, min_reward)
  }
}
