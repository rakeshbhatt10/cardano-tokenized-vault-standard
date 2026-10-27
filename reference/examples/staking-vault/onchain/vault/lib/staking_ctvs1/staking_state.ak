// Staking controller for factory-admitted, script-owned staking positions.
// Synchronous pooled staking: all priced principal belongs to one immutable
// position. Test1-style rewards are a separate basket reserve, never priced as
// principal. Entries buy an equal share of accrued rewards; exits claim and split
// them atomically. No oracle, manager withdrawal or bare Claim action is admitted.
use aiken/builtin
use aiken/collection/list
use aiken/fuzz
use aiken/interval
use cardano/address.{from_script, from_verification_key}
use cardano/assets
use cardano/transaction.{Output, OutputReference, Transaction}
use ctvs/ledger
use ctvs/math.{Quote}
use ctvs/state_core
use ctvs/validation
use ctvs/wire.{
  CollectFees, Datum, Deposit, Destination, MintShares, NativeAsset, Redeem,
  SetPause, State, StateAction, Terms, TopUpReserve, Withdraw,
}
use staking/authorization.{AuthorizeStaking}
use staking/protocol as staking
use staking/rewards
use staking/types.{PoolDatum, PositionDatum}
use staking_ctvs1/controller_decode
use staking_ctvs1/staking_core as core
use staking_ctvs1/types.{PoolBinding} as vault_types

pub fn permits_modes(modes: Int) -> Bool {
  modes == 3
}

pub fn decode_action(raw: Data) -> (StateAction, Int, Int) {
  controller_decode.decode(raw)
}

pub fn output_index(action: StateAction) -> Int {
  when action is {
    Deposit { state_output, .. } |
    MintShares { state_output, .. } |
    Withdraw { state_output, .. } |
    Redeem { state_output, .. } |
    CollectFees { state_output, .. } |
    TopUpReserve { state_output, .. } |
    SetPause { state_output, .. } -> state_output
    _ -> fail
  }
}

fn pool(output: Output) -> PoolDatum {
  let Pair(tag, fields) = builtin.un_constr_data(ledger.raw_datum(output))
  expect tag == 0
  expect [raw_pool] = fields
  expect value: PoolDatum = raw_pool
  value
}

type PositionView {
  schema_version: Int,
  pool_id: ByteArray,
  position_name: ByteArray,
  owner: Data,
  payout_address: Data,
  staked_amount: Int,
  reward_per_token_paid: Int,
  pending_rewards: Int,
}

fn position(
  output: Output,
  binding: PoolBinding,
  owner: ByteArray,
) -> PositionView {
  let name = core.position_name(binding)
  let Pair(tag, fields) = builtin.un_constr_data(ledger.raw_datum(output))
  expect tag == 1
  expect [raw_position] = fields
  expect value: PositionView = raw_position
  let expected_owner: Data = types.VaultOwner {
    controller: owner,
    state_policy: owner,
    state_name: wire.state_name,
  }
  let expected_address: Data = from_script(owner)
  expect and {
      output.address == from_script(binding.pool_policy),
      output.reference_script == None,
      assets.quantity_of(output.value, binding.pool_policy, name) == 1,
      value.pool_id == binding.pool_policy,
      value.position_name == name,
      value.schema_version == 2,
      value.owner == expected_owner,
      value.payout_address == expected_address,
      validation.q(value.staked_amount),
      validation.q(value.pending_rewards),
      value.reward_per_token_paid >= 0,
    }
  value
}

// Authenticate both ends and require the exact staking redeemer. Independent
// pool/position execution proves the full reward checkpoint and reserve rules.
fn staking_change(
  tx: Transaction,
  own_ref: OutputReference,
  policy: ByteArray,
  binding: PoolBinding,
  old_backing: Int,
  old_supply: Int,
  next_backing: Int,
  amount: Int,
  entering: Bool,
) -> Int {
  let pid = binding.pool_policy
  let name = core.position_name(binding)
  expect [pool_input] = list.filter(
    tx.inputs,
    fn(i) {
      assets.quantity_of(i.output.value, pid, staking.pool_token_name) != 0
    },
  )
  expect [pool_output] = list.filter(
    tx.outputs,
    fn(o) { assets.quantity_of(o.value, pid, staking.pool_token_name) != 0 },
  )
  expect and {
      pool_input.output.address == from_script(pid),
      pool_output.address == from_script(pid),
      assets.quantity_of(pool_input.output.value, pid, staking.pool_token_name) == 1,
      assets.quantity_of(pool_output.value, pid, staking.pool_token_name) == 1,
    }
  let before_pool = pool(pool_input.output)
  expect validation.q(before_pool.total_staked)
  expect before_pool.total_staked >= old_backing
  expect !before_pool.is_locked
  expect
    pool(pool_output).total_staked == before_pool.total_staked + next_backing - old_backing
  let applicable = rewards.last_time_reward_applicable(
    before_pool,
    staking.effective_time_seconds(tx),
  )
  let reward_per_token = before_pool.reward_per_token_stored + if before_pool.total_staked == 0 {
    0
  } else {
    ( applicable - before_pool.last_update_seconds ) * before_pool.reward_rate * rewards.precision / before_pool.total_staked
  }
  let positions = list.filter(
    tx.inputs,
    fn(i) { assets.quantity_of(i.output.value, pid, name) != 0 },
  )
  let (creation, earned) = when positions is {
    [] -> {
      expect entering && old_backing == 0 && old_supply == 0
      let creation_input = ledger.input(tx, binding.position_seed)
      expect ledger.key_input(creation_input)
      expect assets.quantity_of(tx.mint, pid, name) == 1
      let expected_identity: Data = staking.OpenPosition {
        schema_version: 2,
        creation_ref: binding.position_seed,
        owner: types.VaultOwner {
          controller: policy,
          state_policy: policy,
          state_name: wire.state_name,
        },
      }
      expect ledger.redeemer(tx, transaction.Mint(pid)) == expected_identity
      (Some(binding.position_seed), 0)
    }
    [input] -> {
      let before = position(input.output, binding, policy)
      expect before.staked_amount == old_backing
      expect before.reward_per_token_paid <= before_pool.reward_per_token_stored
      expect assets.quantity_of(tx.mint, pid, name) == 0
      expect reward_per_token >= before.reward_per_token_paid
      (
        None,
        before.pending_rewards + before.staked_amount * (
          reward_per_token - before.reward_per_token_paid
        ) / rewards.precision,
      )
    }
    _ -> fail
  }
  // decode_action has checked the full State redeemer before this private helper.
  // Bind its exact serialized operation fields to the authenticated transition.
  let Pair(tag, fields) = builtin.un_constr_data(
    ledger.redeemer(tx, transaction.Spend(own_ref)),
  )
  expect tag == 0
  expect  
      [
        _, pool_id, position_name, operation, authorized_amount, creation_ref, _,
        _, _, _,
      ]
    = fields
  let raw_creation: Data = creation
  let raw_operation: Data = if entering {
    authorization.Stake
  } else {
    authorization.WithdrawAndClaim
  }
  expect
    pool_id == builtin.b_data(pid) && position_name == builtin.b_data(name) && authorized_amount == builtin.i_data(
      amount,
    ) && creation_ref == raw_creation && operation == raw_operation
  let action = if entering {
    staking.Stake { amount, position_id: name, creation_ref: creation }
  } else {
    staking.WithdrawAndClaim { amount, position_id: name }
  }
  let raw_action: Data = action
  expect
    ledger.redeemer(tx, transaction.Spend(pool_input.output_reference)) == raw_action
  expect
    list.all(
      positions,
      fn(i) {
        ledger.redeemer(tx, transaction.Spend(i.output_reference)) == raw_action
      },
    )
  expect
    list.all(
      tx.inputs,
      fn(i) {
        i.output_reference == own_ref || i.output_reference == pool_input.output_reference || list.any(
          positions,
          fn(p) { p.output_reference == i.output_reference },
        ) || ledger.key_input(i)
      },
    )
  expect [next_position] = list.filter(
    tx.outputs,
    fn(o) { assets.quantity_of(o.value, pid, name) != 0 },
  )
  let after = position(next_position, binding, policy)
  expect after.staked_amount == next_backing
  expect
    if entering {
      after.pending_rewards == earned
    } else {
      after.pending_rewards == 0
    }
  expect validation.q(earned)
  earned
}

fn direct_next(
  tx: Transaction,
  own_ref: OutputReference,
  old: Datum,
  terms: Terms,
  binding: PoolBinding,
  quote: Quote,
  entering: Bool,
  receiver: Destination,
  receiver_output: Int,
  state_output: Int,
  max_reward_input: Int,
  min_reward_output: Int,
) -> Datum {
  expect  
      State {
        vault_policy,
        backing_assets: a,
        economic_supply: s,
        accrued_fees: f,
        storage_lovelace: r,
        pause_flags,
        ..
      }
    = old
  expect and {
      validation.positive_q(quote.gross),
      validation.positive_q(quote.net),
      validation.positive_q(quote.shares),
      validation.q(quote.fee),
      receiver_output != state_output,
      if entering {
        pause_flags % 2 == 0
      } else {
        pause_flags / 2 == 0
      },
    }
  expect entering || quote.gross <= a && quote.shares <= s
  let next = state_core.next_state(
    old,
    if entering {
      a + quote.net
    } else {
      a - quote.gross
    },
    if entering {
      s + quote.shares
    } else {
      s - quote.shares
    },
    f + quote.fee,
    r,
    pause_flags,
  )
  expect State { backing_assets: next_backing, .. } = next
  let claimed = staking_change(
    tx,
    own_ref,
    vault_policy,
    binding,
    a,
    s,
    next_backing,
    if entering {
      quote.net
    } else {
      quote.gross
    },
    entering,
  )
  let old_rewards = core.reward_balance(
    ledger.input(tx, own_ref).output,
    binding,
  )
  let total_rewards = old_rewards + claimed
  expect validation.q(total_rewards)
  // This must be an explicit expect, not a let whose result is unused on
  // entry. Aiken's lazy lets can otherwise erase the branch's obligations.
  expect
    if entering {
      let buy_in = if s == 0 {
        expect total_rewards == 0
        0
      } else {
        ( total_rewards * quote.shares + s - 1 ) / s
      }
      expect min_reward_output == 0 && buy_in <= max_reward_input
      expect
        core.reward_balance(ledger.output(tx, state_output), binding) == old_rewards + buy_in
      expect
        ledger.economic_payment(
          ledger.output(tx, receiver_output),
          receiver,
          NativeAsset { policy_id: vault_policy, asset_name: wire.share_name },
          quote.shares,
        )
      True
    } else {
      expect s > 0 && max_reward_input == 0
      let payout = total_rewards * quote.shares / s
      expect payout >= min_reward_output
      expect
        core.reward_balance(ledger.output(tx, state_output), binding) == total_rewards - payout
      let output = ledger.output(tx, receiver_output)
      expect NativeAsset { policy_id: rp, asset_name: rn } = binding.reward_asset
      expect ledger.destination_matches(output, receiver)
      expect
        output.value == (
          ledger.economic_value(
            terms.underlying,
            quote.net,
            assets.lovelace_of(output.value),
          )
            |> assets.add(rp, rn, payout)
        )
      True
    }
  next
}

pub fn validate(
  tx: Transaction,
  own_ref: OutputReference,
  policy: ByteArray,
  seed: OutputReference,
  commitment: ByteArray,
  lock_hash: ByteArray,
  action: StateAction,
  max_reward_input: Int,
  min_reward_output: Int,
) -> Bool {
  expect ledger.allowed_purposes(tx)
  let (_, old, terms, binding) = core.authenticate(
    tx,
    own_ref,
    policy,
    seed,
    commitment,
    lock_hash,
    permits_modes,
  )
  expect State { backing_assets: a, economic_supply: s, .. } = old
  let expected = when action is {
    Deposit {
      receiver,
      gross_assets,
      min_shares,
      state_output,
      receiver_output,
    } -> {
      let q = math.quote_deposit(a, s, terms, gross_assets)
      expect q.shares >= min_shares
      direct_next(
        tx,
        own_ref,
        old,
        terms,
        binding,
        q,
        True,
        receiver,
        receiver_output,
        state_output,
        max_reward_input,
        min_reward_output,
      )
    }
    MintShares {
      receiver,
      target_shares,
      max_assets,
      state_output,
      receiver_output,
    } -> {
      let q = math.quote_mint(a, s, terms, target_shares)
      expect q.gross <= max_assets
      direct_next(
        tx,
        own_ref,
        old,
        terms,
        binding,
        q,
        True,
        receiver,
        receiver_output,
        state_output,
        max_reward_input,
        min_reward_output,
      )
    }
    Withdraw { receiver, net_assets, max_shares, state_output, receiver_output } -> {
      let q = math.quote_withdraw(a, s, terms, net_assets)
      expect q.shares <= max_shares
      direct_next(
        tx,
        own_ref,
        old,
        terms,
        binding,
        q,
        False,
        receiver,
        receiver_output,
        state_output,
        max_reward_input,
        min_reward_output,
      )
    }
    Redeem { receiver, shares, min_assets, state_output, receiver_output } -> {
      let q = math.quote_redeem(a, s, terms, shares)
      expect q.net >= min_assets
      direct_next(
        tx,
        own_ref,
        old,
        terms,
        binding,
        q,
        False,
        receiver,
        receiver_output,
        state_output,
        max_reward_input,
        min_reward_output,
      )
    }
    CollectFees { .. } | TopUpReserve { .. } | SetPause { .. } -> {
      expect max_reward_input == 0 && min_reward_output == 0
      expect
        list.all(
          tx.inputs,
          fn(i) { i.output_reference == own_ref || ledger.key_input(i) },
        )
      expect
        core.reward_balance(ledger.output(tx, output_index(action)), binding) == core.reward_balance(
          ledger.input(tx, own_ref).output,
          binding,
        )
      state_core.administrative_next(tx, old, terms, action)
    }
    _ -> fail
  }
  core.validate_successor(
    tx,
    own_ref,
    policy,
    commitment,
    terms,
    old,
    expected,
    output_index(action),
    binding,
  )
}

// Controller component fixtures: staking_change authenticates the position and
// action. Complete controller/pool transactions are evaluated by the local harness.
const test_pool_id = #"11111111111111111111111111111111111111111111111111111111"

const test_controller =
  #"22222222222222222222222222222222222222222222222222222222"

fn test_ref(index: Int) -> OutputReference {
  OutputReference {
    transaction_id: transaction.placeholder.id,
    output_index: index,
  }
}

fn test_binding() -> PoolBinding {
  PoolBinding {
    pool_policy: test_pool_id,
    position_seed: test_ref(3),
    reward_asset: NativeAsset { policy_id: test_controller, asset_name: #"01" },
  }
}

fn test_pool(total: Int) -> PoolDatum {
  PoolDatum {
    total_staked: total,
    reward_duration_seconds: 0,
    period_finish_seconds: 0,
    reward_rate: 0,
    last_update_seconds: 0,
    reward_per_token_stored: 0,
    accrued_liability_bound: 0,
    is_paused: False,
    is_locked: False,
  }
}

fn test_output(name: ByteArray, datum: staking.StakingDatum) -> Output {
  let raw: Data = datum
  Output {
    address: from_script(test_pool_id),
    value: assets.from_asset(test_pool_id, name, 1),
    datum: transaction.InlineDatum(raw),
    reference_script: None,
  }
}

fn test_position(amount: Int) -> PositionDatum {
  PositionDatum {
    schema_version: 2,
    pool_id: test_pool_id,
    position_name: core.position_name(test_binding()),
    owner: types.VaultOwner {
      controller: test_controller,
      state_policy: test_controller,
      state_name: wire.state_name,
    },
    payout_address: from_script(test_controller),
    staked_amount: amount,
    reward_per_token_paid: 0,
    pending_rewards: 0,
  }
}

fn test_topup(entering: Bool) -> Transaction {
  let name = core.position_name(test_binding())
  let action = if entering {
    staking.Stake { amount: 10, position_id: name, creation_ref: None }
  } else {
    staking.WithdrawAndClaim { amount: 10, position_id: name }
  }
  let raw: Data = action
  Transaction {
    ..transaction.placeholder,
    inputs: [
      transaction.Input {
        output_reference: test_ref(1),
        output: test_output(
          staking.pool_token_name,
          staking.Pool(test_pool(300)),
        ),
      },
      transaction.Input {
        output_reference: test_ref(2),
        output: test_output(name, staking.Position(test_position(100))),
      },
    ],
    outputs: [
      test_output(
        staking.pool_token_name,
        staking.Pool(
          test_pool(
            if entering {
              310
            } else {
              290
            },
          ),
        ),
      ),
      test_output(
        name,
        staking.Position(
          test_position(
            if entering {
              110
            } else {
              90
            },
          ),
        ),
      ),
    ],
    redeemers: [
      Pair(transaction.Spend(test_ref(0)), test_authorization(entering, None)),
      Pair(transaction.Spend(test_ref(1)), raw),
      Pair(transaction.Spend(test_ref(2)), raw),
    ],
    validity_range: interval.Interval {
      lower_bound: interval.IntervalBound {
        bound_type: interval.Finite(0),
        is_inclusive: True,
      },
      upper_bound: interval.IntervalBound {
        bound_type: interval.Finite(1000),
        is_inclusive: False,
      },
    },
  }
}

test shared_topup_preserves_other_principal() {
  staking_change(
    test_topup(True),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  ) == 0
}

test shared_exit_preserves_other_principal() {
  staking_change(
    test_topup(False),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    90,
    10,
    False,
  ) == 0
}

test dedicated_total_assignment_rejected() fail {
  let tx = test_topup(True)
  let name = core.position_name(test_binding())
  expect 0 = staking_change(
    Transaction {
      ..tx,
      outputs: [
        test_output(staking.pool_token_name, staking.Pool(test_pool(110))),
        test_output(name, staking.Position(test_position(110))),
      ],
    },
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

test wallet_owner_cannot_impersonate_vault() fail {
  let tx = test_topup(True)
  let name = core.position_name(test_binding())
  let next = PositionDatum {
    ..test_position(110),
    owner: types.WalletOwner(test_controller),
  }
  expect 0 = staking_change(
    Transaction {
      ..tx,
      outputs: [
        test_output(staking.pool_token_name, staking.Pool(test_pool(310))),
        test_output(name, staking.Position(next)),
      ],
    },
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

test wrong_state_identity_rejected() fail {
  let tx = test_topup(True)
  let name = core.position_name(test_binding())
  let next = PositionDatum {
    ..test_position(110),
    owner: types.VaultOwner {
      controller: test_controller,
      state_policy: test_pool_id,
      state_name: wire.state_name,
    },
  }
  expect 0 = staking_change(
    Transaction {
      ..tx,
      outputs: [
        test_output(staking.pool_token_name, staking.Pool(test_pool(310))),
        test_output(name, staking.Position(next)),
      ],
    },
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

test mismatched_staking_action_rejected() fail {
  let tx = test_topup(False)
  expect 0 = staking_change(
    tx,
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    90,
    10,
    True,
  )
}

fn test_first_entry() -> Transaction {
  let name = core.position_name(test_binding())
  let action: Data = staking.Stake {
    amount: 10,
    position_id: name,
    creation_ref: Some(test_ref(3)),
  }
  let identity: Data = staking.OpenPosition {
    schema_version: 2,
    creation_ref: test_ref(3),
    owner: types.VaultOwner {
      controller: test_controller,
      state_policy: test_controller,
      state_name: wire.state_name,
    },
  }
  let base = test_topup(True)
  Transaction {
    ..base,
    inputs: [
      transaction.Input {
        output_reference: test_ref(1),
        output: test_output(
          staking.pool_token_name,
          staking.Pool(test_pool(300)),
        ),
      },
      transaction.Input {
        output_reference: test_ref(3),
        output: Output {
          ..test_output(name, staking.Position(test_position(0))),
          address: from_script(test_controller),
          value: assets.from_lovelace(5_000_000),
        },
      },
    ],
    outputs: [
      test_output(staking.pool_token_name, staking.Pool(test_pool(310))),
      test_output(name, staking.Position(test_position(10))),
    ],
    mint: assets.from_asset(test_pool_id, name, 1),
    redeemers: [
      Pair(
        transaction.Spend(test_ref(0)),
        test_authorization(True, Some(test_ref(3))),
      ),
      Pair(transaction.Spend(test_ref(1)), action),
      Pair(transaction.Mint(test_pool_id), identity),
    ],
  }
}

test first_entry_requires_key_seed() fail {
  expect 0 = staking_change(
    test_first_entry(),
    test_ref(0),
    test_controller,
    test_binding(),
    0,
    0,
    10,
    10,
    True,
  )
}

test first_entry_into_nonempty_pool() {
  let tx = test_first_entry()
  expect [pool_input, seed] = tx.inputs
  let key_seed = transaction.Input {
    ..seed,
    output: Output {
      ..seed.output,
      address: from_verification_key(test_controller),
    },
  }
  staking_change(
    Transaction { ..tx, inputs: [pool_input, key_seed] },
    test_ref(0),
    test_controller,
    test_binding(),
    0,
    0,
    10,
    10,
    True,
  ) == 0
}

test topup_amount_mismatch_rejected() fail {
  expect 0 = staking_change(
    test_topup(True),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    11,
    True,
  )
}

test duplicate_target_position_rejected() fail {
  let tx = test_topup(True)
  expect [pool_input, position_input] = tx.inputs
  expect 0 = staking_change(
    Transaction {
      ..tx,
      inputs: [
        pool_input,
        position_input,
        transaction.Input { ..position_input, output_reference: test_ref(4) },
      ],
    },
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

fn test_authorization(entering: Bool, creation: Option<OutputReference>) -> Data {
  let receiver = Destination {
    address: from_verification_key(test_controller),
    datum: None,
  }
  let action = if entering {
    Deposit {
      receiver,
      gross_assets: 10,
      min_shares: 1,
      state_output: 0,
      receiver_output: 1,
    }
  } else {
    Withdraw {
      receiver,
      net_assets: 10,
      max_shares: 100,
      state_output: 0,
      receiver_output: 1,
    }
  }
  let base: Data = wire.StateSpend {
    magic: wire.magic,
    wire_version: wire.wire_version,
    action,
  }
  let envelope: Data = AuthorizeStaking {
    version: 1,
    pool_id: test_pool_id,
    position_name: core.position_name(test_binding()),
    operation: if entering {
      authorization.Stake
    } else {
      authorization.WithdrawAndClaim
    },
    amount: 10,
    creation_ref: creation,
    state_output: 0,
    base,
    max_reward_input: 0,
    min_reward_output: 0,
  }
  envelope
}

fn test_replace_authorization(field: Int, value: Data) -> Transaction {
  let tx = test_topup(True)
  expect [Pair(purpose, raw), ..rest] = tx.redeemers
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  let changed = list.indexed_map(
    fields,
    fn(i, previous) {
      if i == field {
        value
      } else {
        previous
      }
    },
  )
  Transaction {
    ..tx,
    redeemers: [Pair(purpose, builtin.constr_data(tag, changed)), ..rest],
  }
}

test shared_authorization_wrong_pool_rejected() fail {
  expect 0 = staking_change(
    test_replace_authorization(1, builtin.b_data(test_controller)),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

test shared_authorization_wrong_position_rejected() fail {
  expect 0 = staking_change(
    test_replace_authorization(
      2,
      builtin.b_data(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      ),
    ),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

test shared_authorization_wrong_amount_rejected() fail {
  expect 0 = staking_change(
    test_replace_authorization(4, builtin.i_data(11)),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

test shared_authorization_wrong_creation_mode_rejected() fail {
  let raw: Data = Some(test_ref(3))
  expect 0 = staking_change(
    test_replace_authorization(5, raw),
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    110,
    10,
    True,
  )
}

// Compare the optimized scalar projection with the independent, source-pinned
// reward checkpoint through the controller's actual top-up and exit checks.
fn test_reward_projection(entering: Bool, rate: Int, pending: Int) -> Bool {
  let tx = test_topup(entering)
  let base_pool = test_pool(300)
  let before_pool = PoolDatum {
    ..base_pool,
    reward_duration_seconds: 1000,
    period_finish_seconds: 1000,
    reward_rate: rate,
    reward_per_token_stored: 2 * rewards.precision,
  }
  let initial = test_position(100)
  let before = PositionDatum {
    ..initial,
    pending_rewards: pending,
    reward_per_token_paid: rewards.precision,
  }
  let checkpoint = rewards.checkpoint_pool(before_pool, 10)
  let expected = rewards.checkpoint_position(
    before,
    checkpoint.reward_per_token_stored,
  )
  let next = if entering {
    110
  } else {
    90
  }
  let after = PositionDatum {
    ..expected,
    staked_amount: next,
    pending_rewards: if entering {
      expected.pending_rewards
    } else {
      0
    },
  }
  let evaluated = Transaction {
    ..tx,
    inputs: [
      transaction.Input {
        output_reference: test_ref(1),
        output: test_output(staking.pool_token_name, staking.Pool(before_pool)),
      },
      transaction.Input {
        output_reference: test_ref(2),
        output: test_output(
          core.position_name(test_binding()),
          staking.Position(before),
        ),
      },
    ],
    outputs: [
      test_output(
        staking.pool_token_name,
        staking.Pool(PoolDatum { ..checkpoint, total_staked: 300 + next - 100 }),
      ),
      test_output(core.position_name(test_binding()), staking.Position(after)),
    ],
    validity_range: interval.Interval {
      lower_bound: interval.IntervalBound {
        bound_type: interval.Finite(10_000),
        is_inclusive: True,
      },
      upper_bound: interval.IntervalBound {
        bound_type: interval.Finite(11_000),
        is_inclusive: False,
      },
    },
  }
  staking_change(
    evaluated,
    test_ref(0),
    test_controller,
    test_binding(),
    100,
    100,
    next,
    10,
    entering,
  ) == expected.pending_rewards
}

test nonzero_reward_topup_matches_pinned_checkpoint(
  value via fuzz.int_between(1, 100_000),
) {
  test_reward_projection(True, value, value)
}

test nonzero_reward_exit_matches_pinned_checkpoint(
  value via fuzz.int_between(1, 100_000),
) {
  test_reward_projection(False, value, value)
}
