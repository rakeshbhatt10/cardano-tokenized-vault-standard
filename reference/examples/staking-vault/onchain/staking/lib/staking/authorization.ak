// Shared source contract. No factory admission or permission is granted by decoding.
use aiken/builtin
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/transaction.{OutputReference}

pub type Operation {
  Stake
  WithdrawAndClaim
}

pub type Authorization {
  AuthorizeStaking {
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
  Maintenance { version: Int, base: Data }
}

fn q(n: Int) -> Bool {
  n >= 0 && n <= 9_223_372_036_854_775_807
}

fn index(n: Int) -> Bool {
  n >= 0 && n <= 65535
}

type Base {
  magic: ByteArray,
  version: Int,
  action: Data,
}

type Direct {
  receiver: Data,
  amount: Int,
  bound: Int,
  state_output: Int,
  receiver_output: Int,
}

type Admin {
  first: Int,
  second: Int,
}

pub fn base_info(raw: Data) -> (Int, Int) {
  let Pair(role, envelope_fields) = builtin.un_constr_data(raw)
  expect role == 0 && list.length(envelope_fields) == 3
  expect envelope: Base = raw
  expect envelope.magic == #"43545653" && envelope.version == 2
  let Pair(tag, fields) = builtin.un_constr_data(envelope.action)
  if tag >= 0 && tag <= 3 {
    expect list.length(fields) == 5
    expect action: Direct = builtin.constr_data(0, fields)
    expect
      q(action.amount) && action.amount > 0 && q(action.bound) && action.bound > 0
    expect
      index(action.state_output) && index(action.receiver_output) && action.state_output != action.receiver_output
    (tag, action.state_output)
  } else {
    expect tag >= 5 && tag <= 7 && list.length(fields) == 2
    expect action: Admin = builtin.constr_data(0, fields)
    if tag == 5 {
      expect index(action.first) && index(action.second)
      let result = (tag, action.first)
      result
    } else if tag == 6 {
      expect q(action.first) && action.first > 0 && index(action.second)
      let result = (tag, action.second)
      result
    } else {
      expect action.first >= 0 && action.first <= 3 && index(action.second)
      let result = (tag, action.second)
      result
    }
  }
}

pub fn decode(raw: Data) -> Authorization {
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  expect
    tag == 0 && list.length(fields) == 10 || tag == 1 && list.length(fields) == 2
  expect authorization: Authorization = raw
  when authorization is {
    Maintenance { version, base } -> {
      expect version == 1
      let (action, _) = base_info(base)
      expect action >= 5
      authorization
    }
    AuthorizeStaking {
      version,
      pool_id,
      position_name,
      operation,
      amount,
      creation_ref,
      state_output,
      base,
      max_reward_input,
      min_reward_output,
    } -> {
      expect
        version == 1 && bytearray.length(pool_id) == 28 && bytearray.length(
          position_name,
        ) == 32
      expect
        q(amount) && amount > 0 && index(state_output) && q(max_reward_input) && q(
          min_reward_output,
        )
      // Reject extra operation/option fields before typed projection.
      expect Some(raw_op) = list.at(fields, 3)
      let Pair(op_tag, op_fields) = builtin.un_constr_data(raw_op)
      expect ( op_tag == 0 || op_tag == 1 ) && list.is_empty(op_fields)
      expect Some(raw_creation) = list.at(fields, 5)
      let Pair(creation_tag, creation_fields) = builtin.un_constr_data(
        raw_creation,
      )
      expect
        creation_tag == 0 && list.length(creation_fields) == 1 || creation_tag == 1 && list.is_empty(
          creation_fields,
        )
      expect
        when creation_ref is {
          Some(ref) -> {
            expect Some(raw_ref) = list.at(creation_fields, 0)
            let Pair(ref_tag, ref_fields) = builtin.un_constr_data(raw_ref)
            ref_tag == 0 && list.length(ref_fields) == 2 && bytearray.length(
              ref.transaction_id,
            ) == 32 && index(ref.output_index)
          }
          None -> True
        }
      let (action, inner_output) = base_info(base)
      expect action <= 3 && state_output == inner_output
      expect
        when operation is {
          Stake -> action <= 1 && min_reward_output == 0
          WithdrawAndClaim ->
            action >= 2 && creation_ref == None && max_reward_input == 0
        }
      authorization
    }
  }
}

// Validation of the new immutable pool parameter shape only, not proof of deployment.
pub fn valid_factory_policy(
  vault_supported: Bool,
  factory_policy: Option<ByteArray>,
) -> Bool {
  when factory_policy is {
    Some(policy) -> vault_supported && bytearray.length(policy) == 28
    None -> !vault_supported
  }
}

pub fn staking_action(authorization: Authorization) -> Data {
  when authorization is {
    AuthorizeStaking { operation, amount, position_name, creation_ref, .. } ->
      when operation is {
        Stake -> {
          let creation: Data = creation_ref
          builtin.constr_data(
            0,
            [builtin.i_data(amount), builtin.b_data(position_name), creation],
          )
        }
        WithdrawAndClaim ->
          builtin.constr_data(
            10,
            [builtin.i_data(amount), builtin.b_data(position_name)],
          )
      }
    Maintenance { .. } -> fail
  }
}

// Projection used only together with execution of a factory-admitted controller.
// The controller runs decode(raw) and checks the inner action and all economics;
// staking independently checks the outer operation against its actual effects.
pub fn decode_evidence(raw: Data) -> Authorization {
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  expect tag == 0 && list.length(fields) == 10
  expect approved: Authorization = raw
  expect AuthorizeStaking { version, .. } = approved
  expect version == 1
  approved
}
