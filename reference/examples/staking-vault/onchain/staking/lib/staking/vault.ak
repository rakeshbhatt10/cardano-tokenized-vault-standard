// State permission and transaction correlation. Factory admission is separately
// authenticated at creation; the live validator preserves admitted owner identity.
use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Spend, Transaction}
use staking/authorization.{AuthorizeStaking, Operation, Stake, WithdrawAndClaim}
use staking/types.{PositionOwner, VaultOwner}

pub fn validate_state_permission(
  tx: Transaction,
  owner: PositionOwner,
  payout_address: Address,
  pool_id: PolicyId,
  position_name: AssetName,
  operation: Operation,
  amount: Int,
  creation_ref: Option<OutputReference>,
) -> Bool {
  expect VaultOwner { controller, state_policy, state_name } = owner
  expect controller != pool_id && state_policy != pool_id
  expect payout_address == address.from_script(controller)
  expect
    builtin.length_of_bytearray(controller) == 28 && builtin.length_of_bytearray(
      state_policy,
    ) == 28 && builtin.length_of_bytearray(state_name) <= 32
  expect assets.quantity_of(tx.mint, state_policy, state_name) == 0
  expect [state_input] = list.filter(
    tx.inputs,
    fn(i) { assets.quantity_of(i.output.value, state_policy, state_name) != 0 },
  )
  expect
    state_input.output.address == address.from_script(controller) && assets.quantity_of(
      state_input.output.value,
      state_policy,
      state_name,
    ) == 1
  expect InlineDatum(_) = state_input.output.datum
  expect Some(raw) = pairs.get_first(
    tx.redeemers,
    Spend(state_input.output_reference),
  )
  let approved = authorization.decode_evidence(raw)
  expect  
      AuthorizeStaking {
        pool_id: authorized_pool,
        position_name: authorized_position,
        operation: authorized_operation,
        amount: authorized_amount,
        creation_ref: authorized_creation,
        state_output,
        ..
      }
    = approved
  expect
    authorized_pool == pool_id && authorized_position == position_name && authorized_operation == operation && authorized_amount == amount && authorized_creation == creation_ref
  expect Some(continuation) = list.at(tx.outputs, state_output)
  expect [state_continuation] = list.filter(
    tx.outputs,
    fn(o) { assets.quantity_of(o.value, state_policy, state_name) != 0 },
  )
  expect
    continuation == state_continuation && continuation.address == state_input.output.address
  expect InlineDatum(_) = continuation.datum
  expect assets.quantity_of(continuation.value, state_policy, state_name) == 1
  True
}

// Standalone helper also checks staking purposes. The live validator calls the
// State-only layer because its own mint/spend handlers enforce these same effects.
pub fn validate_operation_evidence(
  tx: Transaction,
  owner: PositionOwner,
  payout_address: Address,
  pool_id: PolicyId,
  position_name: AssetName,
  operation: Operation,
  amount: Int,
  creation_ref: Option<OutputReference>,
) -> Bool {
  expect VaultOwner { state_policy, state_name, .. } = owner
  expect [state] = list.filter(
    tx.inputs,
    fn(i) { assets.quantity_of(i.output.value, state_policy, state_name) != 0 },
  )
  expect Some(raw) = pairs.get_first(
    tx.redeemers,
    Spend(state.output_reference),
  )
  expect AuthorizeStaking { .. } = authorization.decode(raw)
  expect
    validate_state_permission(
      tx,
      owner,
      payout_address,
      pool_id,
      position_name,
      operation,
      amount,
      creation_ref,
    )
  let creation: Data = creation_ref
  let expected_action = when operation is {
    Stake ->
      builtin.constr_data(
        0,
        [builtin.i_data(amount), builtin.b_data(position_name), creation],
      )
    WithdrawAndClaim ->
      builtin.constr_data(
        10,
        [builtin.i_data(amount), builtin.b_data(position_name)],
      )
  }
  expect [pool_input] = list.filter(
    tx.inputs,
    fn(i) { assets.quantity_of(i.output.value, pool_id, #"504f4f4c") != 0 },
  )
  expect pool_input.output.address == address.from_script(pool_id)
  expect assets.quantity_of(pool_input.output.value, pool_id, #"504f4f4c") == 1
  expect
    pairs.get_first(tx.redeemers, Spend(pool_input.output_reference)) == Some(
      expected_action,
    )
  let positions = list.filter(
    tx.inputs,
    fn(i) { assets.quantity_of(i.output.value, pool_id, position_name) != 0 },
  )
  expect
    when creation_ref is {
      Some(ref) -> {
        expect operation == Stake && list.is_empty(positions)
        expect list.any(tx.inputs, fn(i) { i.output_reference == ref })
        dict.to_pairs(assets.tokens(tx.mint, pool_id)) == [
          Pair(position_name, 1),
        ]
      }
      None -> {
        expect [position_input] = positions
        expect position_input.output.address == address.from_script(pool_id)
        expect
          assets.quantity_of(
            position_input.output.value,
            pool_id,
            position_name,
          ) == 1
        expect
          pairs.get_first(tx.redeemers, Spend(position_input.output_reference)) == Some(
            expected_action,
          )
        dict.is_empty(assets.tokens(tx.mint, pool_id))
      }
    }
  expect
    list.length(
      list.filter(
        tx.inputs,
        fn(i) { i.output.address.payment_credential == address.Script(pool_id) },
      ),
    ) == if creation_ref == None {
      2
    } else {
      1
    }
  True
}

pub fn validate_stake_evidence(
  tx: Transaction,
  owner: PositionOwner,
  payout_address: Address,
  pool_id: PolicyId,
  position_name: AssetName,
  amount: Int,
  creation_ref: Option<OutputReference>,
) -> Bool {
  validate_operation_evidence(
    tx,
    owner,
    payout_address,
    pool_id,
    position_name,
    Stake,
    amount,
    creation_ref,
  )
}

pub fn validate_exit_evidence(
  tx: Transaction,
  owner: PositionOwner,
  payout_address: Address,
  pool_id: PolicyId,
  position_name: AssetName,
  amount: Int,
) -> Bool {
  validate_operation_evidence(
    tx,
    owner,
    payout_address,
    pool_id,
    position_name,
    WithdrawAndClaim,
    amount,
    None,
  )
}
