// Purpose-scoped synchronous decoder. Reject asynchronous tags before decoding
// their payloads, retaining the public WIRE-2 tag numbers and exact field counts.
use aiken/builtin
use ctvs/validation
use ctvs/wire.{
  CollectFees, Deposit, Destination, MintShares, Redeem, SetPause, StateAction,
  TopUpReserve, Withdraw,
}

type Direct {
  receiver: Destination,
  amount: Int,
  bound: Int,
  state_output: Int,
  receiver_output: Int,
}

type TwoInts {
  first: Int,
  second: Int,
}

pub fn action(raw: Data) -> StateAction {
  let Pair(envelope_tag, envelope_fields) = builtin.un_constr_data(raw)
  expect envelope_tag == 0
  expect [magic, version, raw_action] = envelope_fields
  expect
    magic == builtin.b_data(wire.magic) && version == builtin.i_data(
      wire.wire_version,
    )
  let Pair(tag, fields) = builtin.un_constr_data(raw_action)
  if tag >= 0 && tag <= 3 {
    expect [receiver, amount, bound, successor, payout] = fields
    expect destination: Destination = receiver
    let d = Direct {
      receiver: destination,
      amount: builtin.un_i_data(amount),
      bound: builtin.un_i_data(bound),
      state_output: builtin.un_i_data(successor),
      receiver_output: builtin.un_i_data(payout),
    }
    expect and {
        validation.valid_destination(d.receiver),
        validation.positive_q(d.amount),
        validation.positive_q(d.bound),
        validation.valid_index(d.state_output),
        validation.valid_index(d.receiver_output),
        d.state_output != d.receiver_output,
      }
    when tag is {
      0 ->
        Deposit {
          receiver: d.receiver,
          gross_assets: d.amount,
          min_shares: d.bound,
          state_output: d.state_output,
          receiver_output: d.receiver_output,
        }
      1 ->
        MintShares {
          receiver: d.receiver,
          target_shares: d.amount,
          max_assets: d.bound,
          state_output: d.state_output,
          receiver_output: d.receiver_output,
        }
      2 ->
        Withdraw {
          receiver: d.receiver,
          net_assets: d.amount,
          max_shares: d.bound,
          state_output: d.state_output,
          receiver_output: d.receiver_output,
        }
      _ ->
        Redeem {
          receiver: d.receiver,
          shares: d.amount,
          min_assets: d.bound,
          state_output: d.state_output,
          receiver_output: d.receiver_output,
        }
    }
  } else {
    expect tag >= 5 && tag <= 7
    expect [first, second] = fields
    let d = TwoInts {
      first: builtin.un_i_data(first),
      second: builtin.un_i_data(second),
    }
    expect validation.valid_index(d.second)
    when tag is {
      5 -> {
        expect validation.valid_index(d.first) && d.first != d.second
        CollectFees { state_output: d.first, fee_output: d.second }
      }
      6 -> {
        expect validation.positive_q(d.first)
        TopUpReserve { additional_lovelace: d.first, state_output: d.second }
      }
      _ -> {
        expect d.first >= 0 && d.first <= 3
        SetPause { pause_flags: d.first, state_output: d.second }
      }
    }
  }
}
