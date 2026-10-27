use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{VerificationKeyHash, blake2b_256}
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction,
}
use staking/admission
use staking/authorization
use staking/rewards
use staking/types.{
  PoolDatum, PositionDatum, PositionOwner, VaultOwner, WalletOwner,
  position_schema_version,
}
use staking/vault

// Pool identity, position ownership, staking and administrator transitions.
pub type AssetClass {
  policy_id: PolicyId,
  token_name: AssetName,
}

pub type PoolConfig {
  bootstrap_ref: OutputReference,
  manager: VerificationKeyHash,
  rewards_distributor: VerificationKeyHash,
  staking_asset: AssetClass,
  reward_asset: AssetClass,
  initially_locked: Bool,
  vault_supported: Bool,
  factory_policy: Option<PolicyId>,
}

pub type StakingDatum {
  Pool(PoolDatum)
  Position(PositionDatum)
}

pub type IdentityAction {
  InitializePool
  OpenPosition {
    schema_version: Int,
    creation_ref: OutputReference,
    owner: PositionOwner,
  }
  ClosePosition { position_id: AssetName }
}

// No claimed reward amount: the validator will derive it from authentic state.
pub type StakingAction {
  Stake {
    amount: Int,
    position_id: AssetName,
    creation_ref: Option<OutputReference>,
  }
  Withdraw { amount: Int, position_id: AssetName }
  Claim { position_id: AssetName }
  Exit { position_id: AssetName }
  CloseEmptyPosition { position_id: AssetName }
  NotifyRewards { reward: Int, duration_seconds: Int }
  FundRewards { amount: Int }
  TogglePause
  ToggleWithdrawLock
  RecoverSurplus { asset: AssetClass, amount: Int }
  WithdrawAndClaim { amount: Int, position_id: AssetName }
}

validator single_staking(
  bootstrap_ref: OutputReference,
  manager: VerificationKeyHash,
  rewards_distributor: VerificationKeyHash,
  staking_asset: AssetClass,
  reward_asset: AssetClass,
  initially_locked: Bool,
  vault_supported: Bool,
  factory_policy: Option<PolicyId>,
) {
  mint(redeemer: IdentityAction, policy_id: PolicyId, self: Transaction) {
    let config = PoolConfig {
      bootstrap_ref,
      manager,
      rewards_distributor,
      staking_asset,
      reward_asset,
      initially_locked,
      vault_supported,
      factory_policy,
    }
    when redeemer is {
      InitializePool -> validate_initialize_pool(config, policy_id, self)
      OpenPosition { schema_version, creation_ref, owner } -> {
        expect schema_version == position_schema_version
        validate_open_position(config, policy_id, creation_ref, owner, self)
      }
      ClosePosition { position_id } ->
        validate_close_position(config, policy_id, position_id, self)
    }
  }

  spend(
    datum: Option<StakingDatum>,
    redeemer: StakingAction,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(state) = datum
    let config = PoolConfig {
      bootstrap_ref,
      manager,
      rewards_distributor,
      staking_asset,
      reward_asset,
      initially_locked,
      vault_supported,
      factory_policy,
    }
    when state is {
      Position(position) ->
        validate_position_spend(config, position, redeemer, own_ref, self)
      Pool(pool) ->
        when redeemer is {
          Stake { amount, position_id, creation_ref } ->
            validate_stake(
              config,
              pool,
              amount,
              position_id,
              creation_ref,
              own_ref,
              self,
            )
          WithdrawAndClaim { amount, position_id } ->
            validate_withdraw_and_claim(
              config,
              pool,
              amount,
              position_id,
              own_ref,
              self,
            )
          Withdraw { amount, position_id } ->
            validate_withdraw(config, pool, amount, position_id, own_ref, self)
          Claim { position_id } ->
            validate_claim(config, pool, position_id, own_ref, self)
          Exit { position_id } ->
            validate_exit(config, pool, position_id, own_ref, self)
          CloseEmptyPosition { position_id } ->
            validate_close_empty_position(
              config,
              pool,
              position_id,
              own_ref,
              self,
            )
          NotifyRewards { reward, duration_seconds } ->
            validate_notify_rewards(
              config,
              pool,
              reward,
              duration_seconds,
              own_ref,
              self,
            )
          FundRewards { amount } ->
            validate_fund_rewards(config, pool, amount, own_ref, self)
          TogglePause -> validate_toggle_pause(config, pool, own_ref, self)
          ToggleWithdrawLock ->
            validate_toggle_lock(config, pool, own_ref, self)
          RecoverSurplus { asset, amount } ->
            validate_recover_surplus(config, pool, asset, amount, own_ref, self)
        }
    }
  }

  else(_) {
    fail
  }
}

// Pool name and position hash lengths are disjoint (4 bytes versus 32 bytes).
pub const pool_token_name = #"504f4f4c"

// Stable naming: blake2b_256(CBOR-encoded OutputReference as Plutus Data).
pub fn position_token_name(creation_ref: OutputReference) -> AssetName {
  let data: Data = creation_ref
  blake2b_256(builtin.serialise_data(data))
}

fn valid_hash(hash: ByteArray) -> Bool {
  builtin.length_of_bytearray(hash) == 28
}

fn valid_asset(asset: AssetClass, own_policy: PolicyId) -> Bool {
  and {
    valid_hash(asset.policy_id),
    builtin.length_of_bytearray(asset.token_name) <= 32,
    asset.policy_id != own_policy,
  }
}

fn valid_config(config: PoolConfig, policy_id: PolicyId) -> Bool {
  and {
    valid_hash(config.manager),
    valid_hash(config.rewards_distributor),
    builtin.length_of_bytearray(config.bootstrap_ref.transaction_id) == 32,
    config.bootstrap_ref.output_index >= 0,
    valid_asset(config.staking_asset, policy_id),
    valid_asset(config.reward_asset, policy_id),
  }
}

fn exact_identity_tokens(
  value: assets.Value,
  policy_id: PolicyId,
  name: AssetName,
  quantity: Int,
) -> Bool {
  dict.to_pairs(assets.tokens(value, policy_id)) == [Pair(name, quantity)]
}

fn exact_mint(
  self: Transaction,
  policy_id: PolicyId,
  name: AssetName,
  quantity: Int,
) -> Bool {
  exact_identity_tokens(self.mint, policy_id, name, quantity)
}

fn marker_only(output: Output, policy_id: PolicyId, name: AssetName) -> Bool {
  and {
    output.address == address.from_script(policy_id),
    exact_identity_tokens(output.value, policy_id, name, 1),
  }
}

// New positions contain only their marker and minimum ADA, never principal.
fn position_value(output: Output, policy_id: PolicyId, name: AssetName) -> Bool {
  and {
    marker_only(output, policy_id, name),
    list.all(
      assets.flatten(output.value),
      fn(entry) {
        let (pid, tn, _) = entry
        pid == #"" || pid == policy_id && tn == name
      },
    ),
  }
}

fn pool_input(self: Transaction, policy_id: PolicyId) -> Input {
  expect [input] = list.filter(
    self.inputs,
    fn(input) {
      assets.quantity_of(input.output.value, policy_id, pool_token_name) != 0
    },
  )
  expect marker_only(input.output, policy_id, pool_token_name)
  input
}

fn pool_output(self: Transaction, policy_id: PolicyId) -> Output {
  expect [output] = list.filter(
    self.outputs,
    fn(output) {
      assets.quantity_of(output.value, policy_id, pool_token_name) != 0
    },
  )
  expect marker_only(output, policy_id, pool_token_name)
  output
}

fn read_pool(output: Output) -> PoolDatum {
  expect InlineDatum(raw) = output.datum
  expect datum: StakingDatum = raw
  expect Pool(pool) = datum
  pool
}

fn read_position(output: Output) -> PositionDatum {
  expect InlineDatum(raw) = output.datum
  expect datum: StakingDatum = raw
  expect Position(position) = datum
  expect position.schema_version == position_schema_version
  position
}

fn spending_action(self: Transaction, ref: OutputReference) -> StakingAction {
  expect Some(raw) = pairs.get_first(self.redeemers, Spend(ref))
  expect action: StakingAction = raw
  action
}

fn script_input_count(self: Transaction, policy_id: PolicyId) -> Int {
  list.length(
    list.filter(
      self.inputs,
      fn(input) {
        input.output.address.payment_credential == address.Script(policy_id)
      },
    ),
  )
}

fn validate_initialize_pool(
  config: PoolConfig,
  policy_id: PolicyId,
  self: Transaction,
) -> Bool {
  expect
    authorization.valid_factory_policy(
      config.vault_supported,
      config.factory_policy,
    )
  expect !config.vault_supported || !config.initially_locked
  expect valid_config(config, policy_id)
  expect exact_mint(self, policy_id, pool_token_name, 1)
  expect list.has(self.extra_signatories, config.manager)
  expect
    list.any(
      self.inputs,
      fn(input) { input.output_reference == config.bootstrap_ref },
    )
  // Never accept preexisting identity tokens or script-state inputs at bootstrap.
  expect
    list.all(
      self.inputs,
      fn(input) { dict.is_empty(assets.tokens(input.output.value, policy_id)) },
    )
  expect script_input_count(self, policy_id) == 0
  let output = pool_output(self, policy_id)
  let pool = read_pool(output)
  and {
    pool == PoolDatum {
      total_staked: 0,
      reward_duration_seconds: 0,
      period_finish_seconds: 0,
      reward_rate: 0,
      last_update_seconds: 0,
      reward_per_token_stored: 0,
      accrued_liability_bound: 0,
      is_paused: False,
      is_locked: config.initially_locked,
    },
    position_value(output, policy_id, pool_token_name),
  }
}

// Share identical wallet checks to keep inline transaction witnesses within size limits.
fn wallet_position_authorized(
  self: Transaction,
  position: PositionDatum,
) -> Bool {
  expect WalletOwner(owner) = position.owner
  and {
    valid_hash(owner),
    position.payout_address.payment_credential == VerificationKey(owner),
    list.has(self.extra_signatories, owner),
  }
}

fn position_operation_authorized(
  config: PoolConfig,
  policy_id: PolicyId,
  position: PositionDatum,
  operation: authorization.Operation,
  amount: Int,
  creation_ref: Option<OutputReference>,
  self: Transaction,
) -> Bool {
  when position.owner is {
    WalletOwner(_) -> wallet_position_authorized(self, position)
    VaultOwner { .. } -> {
      expect config.vault_supported && !config.initially_locked
      expect Some(factory) = config.factory_policy
      expect config.staking_asset != config.reward_asset
      expect
        when creation_ref is {
          Some(seed) ->
            admission.validate(
              self,
              factory,
              position.owner,
              policy_id,
              seed,
              admission.NativeAsset {
                policy_id: config.staking_asset.policy_id,
                asset_name: config.staking_asset.token_name,
              },
              admission.NativeAsset {
                policy_id: config.reward_asset.policy_id,
                asset_name: config.reward_asset.token_name,
              },
            )
          None -> True
        }
      vault.validate_state_permission(
        self,
        position.owner,
        position.payout_address,
        policy_id,
        position.position_name,
        operation,
        amount,
        creation_ref,
      )
    }
  }
}

fn validate_open_position(
  config: PoolConfig,
  policy_id: PolicyId,
  creation_ref: OutputReference,
  owner: PositionOwner,
  self: Transaction,
) -> Bool {
  expect valid_config(config, policy_id)
  let name = position_token_name(creation_ref)
  expect exact_mint(self, policy_id, name, 1)
  expect
    list.any(self.inputs, fn(input) { input.output_reference == creation_ref })
  expect script_input_count(self, policy_id) == 1
  let input = pool_input(self, policy_id)
  expect input.output_reference != creation_ref
  let before = read_pool(input.output)
  expect !before.is_paused
  expect Stake { amount, position_id, creation_ref: action_ref } = spending_action(
    self,
    input.output_reference,
  )
  expect and {
      amount > 0,
      position_id == name,
      action_ref == Some(creation_ref),
    }
  let output = pool_output(self, policy_id)
  let after = read_pool(output)
  expect [position_output] = list.filter(
    self.outputs,
    fn(out) { assets.quantity_of(out.value, policy_id, name) != 0 },
  )
  let position = read_position(position_output)
  and {
    position_value(position_output, policy_id, name),
    position.pool_id == policy_id,
    position.position_name == name,
    position.owner == owner,
    position_operation_authorized(
      config,
      policy_id,
      position,
      authorization.Stake,
      amount,
      Some(creation_ref),
      self,
    ),
    position.staked_amount == amount,
    position.pending_rewards == 0,
    position.reward_per_token_paid == after.reward_per_token_stored,
    after.total_staked == before.total_staked + amount,
    assets.quantity_of(
      output.value,
      config.staking_asset.policy_id,
      config.staking_asset.token_name,
    ) == assets.quantity_of(
      input.output.value,
      config.staking_asset.policy_id,
      config.staking_asset.token_name,
    ) + amount,
  }
  // The matching pool spend independently validates accrual, fields and reserves.
}

fn validate_close_position(
  config: PoolConfig,
  policy_id: PolicyId,
  position_id: AssetName,
  self: Transaction,
) -> Bool {
  expect valid_config(config, policy_id)
  expect builtin.length_of_bytearray(position_id) == 32
  expect exact_mint(self, policy_id, position_id, -1)
  expect script_input_count(self, policy_id) == 2
  let input = pool_input(self, policy_id)
  let before = read_pool(input.output)
  let after = read_pool(pool_output(self, policy_id))
  expect [position_input] = list.filter(
    self.inputs,
    fn(i) { assets.quantity_of(i.output.value, policy_id, position_id) != 0 },
  )
  expect position_value(position_input.output, policy_id, position_id)
  let position = read_position(position_input.output)
  expect and {
      position.pool_id == policy_id,
      position.position_name == position_id,
      wallet_position_authorized(self, position),
      position.staked_amount >= 0,
      position.pending_rewards >= 0,
    }
  let action = spending_action(self, input.output_reference)
  expect spending_action(self, position_input.output_reference) == action
  expect
    list.all(
      self.outputs,
      fn(out) { assets.quantity_of(out.value, policy_id, position_id) == 0 },
    )
  when action is {
    Exit { position_id: id } -> and {
        id == position_id,
        after.total_staked == before.total_staked - position.staked_amount,
        after.total_staked >= 0,
      }
    CloseEmptyPosition { position_id: id } -> and {
        id == position_id,
        position.staked_amount == 0,
        position.pending_rewards == 0,
        after.total_staked == before.total_staked,
      }
    _ -> False
  }
  // Pool/position spend handlers enforce payout, lock, rewards and returned ADA.
}

// Position spends must be coupled to the exact authenticated pool transition.
fn validate_position_spend(
  config: PoolConfig,
  position: PositionDatum,
  action: StakingAction,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  let input = pool_input(self, position.pool_id)
  expect spending_action(self, input.output_reference) == action
  expect [own_input] = list.filter(
    self.inputs,
    fn(i) { i.output_reference == own_ref },
  )
  expect
    position_value(own_input.output, position.pool_id, position.position_name)
  expect read_position(own_input.output) == position
  when action is {
    Stake { amount, position_id, creation_ref: None } -> and {
        position_id == position.position_name,
        validate_stake(
          config,
          read_pool(input.output),
          amount,
          position_id,
          None,
          input.output_reference,
          self,
        ),
      }
    WithdrawAndClaim { amount, position_id } -> and {
        position_id == position.position_name,
        validate_withdraw_and_claim(
          config,
          read_pool(input.output),
          amount,
          position_id,
          input.output_reference,
          self,
        ),
      }
    Withdraw { amount, position_id } -> and {
        position_id == position.position_name,
        validate_withdraw(
          config,
          read_pool(input.output),
          amount,
          position_id,
          input.output_reference,
          self,
        ),
      }
    Claim { position_id } -> and {
        position_id == position.position_name,
        validate_claim(
          config,
          read_pool(input.output),
          position_id,
          input.output_reference,
          self,
        ),
      }
    Exit { position_id } -> and {
        position_id == position.position_name,
        validate_exit(
          config,
          read_pool(input.output),
          position_id,
          input.output_reference,
          self,
        ),
      }
    CloseEmptyPosition { position_id } -> and {
        position_id == position.position_name,
        validate_close_empty_position(
          config,
          read_pool(input.output),
          position_id,
          input.output_reference,
          self,
        ),
      }
    _ -> fail @"Unsupported position action"
  }
}

fn validate_stake(
  config: PoolConfig,
  pool: PoolDatum,
  amount: Int,
  position_id: AssetName,
  creation_ref: Option<OutputReference>,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect and {
      amount > 0,
      !pool.is_paused,
      builtin.length_of_bytearray(position_id) == 32,
    }
  expect [own_input] = list.filter(
    self.inputs,
    fn(i) { i.output_reference == own_ref },
  )
  expect address.Script(policy_id) = own_input.output.address.payment_credential
  expect valid_config(config, policy_id)
  expect pool_input(self, policy_id).output_reference == own_ref
  expect read_pool(own_input.output) == pool
  let time = effective_time_seconds(self)
  let checkpoint = rewards.checkpoint_pool(pool, time)
  let output = pool_output(self, policy_id)
  let after = read_pool(output)
  expect
    after == PoolDatum {
      ..checkpoint,
      total_staked: pool.total_staked + amount,
    }
  expect [position_output] = list.filter(
    self.outputs,
    fn(out) { assets.quantity_of(out.value, policy_id, position_id) != 0 },
  )
  expect position_value(position_output, policy_id, position_id)
  let next_position = read_position(position_output)
  expect and {
      next_position.pool_id == policy_id,
      next_position.position_name == position_id,
      position_operation_authorized(
        config,
        policy_id,
        next_position,
        authorization.Stake,
        amount,
        creation_ref,
        self,
      ),
    }
  when creation_ref is {
    Some(ref) -> {
      expect script_input_count(self, policy_id) == 1
      expect position_token_name(ref) == position_id
      expect ref != own_ref
      expect list.any(self.inputs, fn(i) { i.output_reference == ref })
      expect exact_mint(self, policy_id, position_id, 1)
      expect
        list.all(
          self.inputs,
          fn(i) {
            i.output_reference == own_ref || dict.is_empty(
              assets.tokens(i.output.value, policy_id),
            )
          },
        )
      expect and {
          next_position.staked_amount == amount,
          next_position.pending_rewards == 0,
          next_position.reward_per_token_paid == checkpoint.reward_per_token_stored,
        }
    }
    None -> {
      expect script_input_count(self, policy_id) == 2
      expect dict.is_empty(assets.tokens(self.mint, policy_id))
      expect [position_input] = list.filter(
        self.inputs,
        fn(i) {
          assets.quantity_of(i.output.value, policy_id, position_id) != 0
        },
      )
      expect position_value(position_input.output, policy_id, position_id)
      let previous = read_position(position_input.output)
      expect and {
          previous.pool_id == policy_id,
          previous.position_name == position_id,
          previous.owner == next_position.owner,
          previous.staked_amount >= 0,
          previous.pending_rewards >= 0,
          previous.reward_per_token_paid <= pool.reward_per_token_stored,
        }
      expect
        spending_action(self, position_input.output_reference) == Stake {
          amount,
          position_id,
          creation_ref: None,
        }
      let accrued = rewards.checkpoint_position(
        previous,
        checkpoint.reward_per_token_stored,
      )
      expect
        next_position == PositionDatum {
          ..accrued,
          staked_amount: previous.staked_amount + amount,
        }
      expect
        assets.lovelace_of(position_output.value) >= assets.lovelace_of(
          position_input.output.value,
        )
      expect
        list.all(
          self.inputs,
          fn(i) {
            i.output_reference == own_ref || i.output_reference == position_input.output_reference || dict.is_empty(
              assets.tokens(i.output.value, policy_id),
            )
          },
        )
    }
  }
  expect
    list.all(
      self.outputs,
      fn(out) {
        out == output || out == position_output || dict.is_empty(
          assets.tokens(out.value, policy_id),
        )
      },
    )
  let stake = config.staking_asset
  let reward_asset = config.reward_asset
  let old_stake = assets.quantity_of(
    own_input.output.value,
    stake.policy_id,
    stake.token_name,
  )
  let new_stake = assets.quantity_of(
    output.value,
    stake.policy_id,
    stake.token_name,
  )
  let reward_balance = assets.quantity_of(
    output.value,
    reward_asset.policy_id,
    reward_asset.token_name,
  )
  let remaining = if pool.period_finish_seconds > time {
    pool.period_finish_seconds - time
  } else {
    0
  }
  and {
    old_stake >= pool.total_staked,
    new_stake == old_stake + amount,
    list.all(
      assets.flatten(own_input.output.value),
      fn(entry) {
        let (pid, name, quantity) = entry
        assets.quantity_of(output.value, pid, name) >= quantity
      },
    ),
    reward_balance >= checkpoint.accrued_liability_bound + remaining * pool.reward_rate + if stake == reward_asset {
      after.total_staked
    } else {
      0
    },
  }
}

fn validate_withdraw(
  config: PoolConfig,
  pool: PoolDatum,
  amount: Int,
  position_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_settlement(
    config,
    pool,
    position_id,
    own_ref,
    self,
    Withdraw { amount, position_id },
  )
}

fn validate_claim(
  config: PoolConfig,
  pool: PoolDatum,
  position_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_settlement(
    config,
    pool,
    position_id,
    own_ref,
    self,
    Claim { position_id },
  )
}

fn validate_withdraw_and_claim(
  config: PoolConfig,
  pool: PoolDatum,
  amount: Int,
  position_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_settlement(
    config,
    pool,
    position_id,
    own_ref,
    self,
    WithdrawAndClaim { amount, position_id },
  )
}

fn validate_exit(
  config: PoolConfig,
  pool: PoolDatum,
  position_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_settlement(
    config,
    pool,
    position_id,
    own_ref,
    self,
    Exit { position_id },
  )
}

fn validate_close_empty_position(
  config: PoolConfig,
  pool: PoolDatum,
  position_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_settlement(
    config,
    pool,
    position_id,
    own_ref,
    self,
    CloseEmptyPosition { position_id },
  )
}

fn paid_to(
  self: Transaction,
  destination: address.Address,
  asset: AssetClass,
) -> Int {
  list.foldl(
    self.outputs,
    0,
    fn(o, total) {
      if o.address == destination {
        total + assets.quantity_of(o.value, asset.policy_id, asset.token_name)
      } else {
        total
      }
    },
  )
}

// One settlement engine preserves identical reserve, identity and storage rules
// for standalone wallet actions, combined exits and wallet position closure.
fn validate_settlement(
  config: PoolConfig,
  pool: PoolDatum,
  position_id: AssetName,
  own_ref: OutputReference,
  self: Transaction,
  action: StakingAction,
) -> Bool {
  expect builtin.length_of_bytearray(position_id) == 32
  expect [own_input] = list.filter(
    self.inputs,
    fn(i) { i.output_reference == own_ref },
  )
  expect address.Script(policy_id) = own_input.output.address.payment_credential
  expect valid_config(config, policy_id)
  expect pool_input(self, policy_id).output_reference == own_ref
  expect read_pool(own_input.output) == pool
  expect script_input_count(self, policy_id) == 2
  expect [position_input] = list.filter(
    self.inputs,
    fn(i) { assets.quantity_of(i.output.value, policy_id, position_id) != 0 },
  )
  expect position_value(position_input.output, policy_id, position_id)
  let previous = read_position(position_input.output)
  expect previous.pool_id == policy_id && previous.position_name == position_id
  expect
    previous.staked_amount >= 0 && previous.staked_amount <= pool.total_staked
  let (amount, claiming, closing) = when action is {
    Withdraw { amount, .. } -> {
      expect amount > 0
      (amount, False, False)
    }
    Claim { .. } -> (0, True, False)
    WithdrawAndClaim { amount, .. } -> {
      expect amount > 0
      (amount, True, False)
    }
    Exit { .. } -> (previous.staked_amount, True, True)
    CloseEmptyPosition { .. } -> {
      expect previous.staked_amount == 0 && previous.pending_rewards == 0
      (0, True, True)
    }
    _ -> fail
  }
  expect amount <= previous.staked_amount
  expect
    when action is {
      WithdrawAndClaim { .. } ->
        position_operation_authorized(
          config,
          policy_id,
          previous,
          authorization.WithdrawAndClaim,
          amount,
          None,
          self,
        )
      _ -> wallet_position_authorized(self, previous)
    }
  expect spending_action(self, own_ref) == action
  expect spending_action(self, position_input.output_reference) == action
  let time = effective_time_seconds(self)
  expect amount == 0 || !pool.is_locked || time > pool.period_finish_seconds
  let checkpoint = rewards.checkpoint_pool(pool, time)
  let accrued = rewards.checkpoint_position(
    previous,
    checkpoint.reward_per_token_stored,
  )
  let claim = if claiming {
    accrued.pending_rewards
  } else {
    0
  }
  expect claim <= checkpoint.accrued_liability_bound
  let after = PoolDatum {
    ..checkpoint,
    total_staked: pool.total_staked - amount,
    accrued_liability_bound: checkpoint.accrued_liability_bound - claim,
  }
  let output = pool_output(self, policy_id)
  expect read_pool(output) == after
  expect
    if closing {
      expect validate_close_position(config, policy_id, position_id, self)
      list.all(
        self.outputs,
        fn(o) {
          o == output || dict.is_empty(assets.tokens(o.value, policy_id))
        },
      )
    } else {
      expect dict.is_empty(assets.tokens(self.mint, policy_id))
      expect [position_output] = list.filter(
        self.outputs,
        fn(o) { assets.quantity_of(o.value, policy_id, position_id) != 0 },
      )
      expect position_value(position_output, policy_id, position_id)
      expect
        read_position(position_output) == PositionDatum {
          ..accrued,
          staked_amount: previous.staked_amount - amount,
          pending_rewards: accrued.pending_rewards - claim,
        }
      expect
        assets.lovelace_of(position_output.value) >= assets.lovelace_of(
          position_input.output.value,
        )
      list.all(
        self.outputs,
        fn(o) {
          o == output || o == position_output || dict.is_empty(
            assets.tokens(o.value, policy_id),
          )
        },
      )
    }
  expect
    list.all(
      self.inputs,
      fn(i) {
        i.output_reference == own_ref || i.output_reference == position_input.output_reference || dict.is_empty(
          assets.tokens(i.output.value, policy_id),
        )
      },
    )
  let stake = config.staking_asset
  let reward = config.reward_asset
  let deduction = fn(pid, name) {
    let principal = if pid == stake.policy_id && name == stake.token_name {
      amount
    } else {
      0
    }
    let earned = if pid == reward.policy_id && name == reward.token_name {
      claim
    } else {
      0
    }
    principal + earned
  }
  let new_stake = assets.quantity_of(
    output.value,
    stake.policy_id,
    stake.token_name,
  )
  let new_reward = assets.quantity_of(
    output.value,
    reward.policy_id,
    reward.token_name,
  )
  let remaining = if pool.period_finish_seconds > time {
    pool.period_finish_seconds - time
  } else {
    0
  }
  let reserves_valid = and {
    new_stake == assets.quantity_of(
      own_input.output.value,
      stake.policy_id,
      stake.token_name,
    ) - deduction(stake.policy_id, stake.token_name),
    new_reward == assets.quantity_of(
      own_input.output.value,
      reward.policy_id,
      reward.token_name,
    ) - deduction(reward.policy_id, reward.token_name),
    list.all(
      assets.flatten(own_input.output.value),
      fn(entry) {
        let (pid, name, quantity) = entry
        assets.quantity_of(output.value, pid, name) >= quantity - deduction(
          pid,
          name,
        )
      },
    ),
    new_stake >= after.total_staked,
    new_reward >= after.accrued_liability_bound + remaining * pool.reward_rate + if stake == reward {
      after.total_staked
    } else {
      0
    },
  }
  reserves_valid && when previous.owner is {
    WalletOwner(_) -> and {
        paid_to(self, previous.payout_address, stake) >= deduction(
          stake.policy_id,
          stake.token_name,
        ),
        paid_to(self, previous.payout_address, reward) >= deduction(
          reward.policy_id,
          reward.token_name,
        ),
        if closing {
          paid_to(
            self,
            previous.payout_address,
            AssetClass { policy_id: #"", token_name: #"" },
          ) >= assets.lovelace_of(position_input.output.value)
        } else {
          True
        },
      }
    VaultOwner { .. } -> True
  }
}

// Common authentication for single-pool administrative transitions. No position identity moves.
fn authenticate_pool_transition(
  config: PoolConfig,
  pool: PoolDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> (PolicyId, Input, Output) {
  expect [own_input] = list.filter(
    self.inputs,
    fn(i) { i.output_reference == own_ref },
  )
  expect address.Script(policy_id) = own_input.output.address.payment_credential
  expect valid_config(config, policy_id)
  expect pool_input(self, policy_id).output_reference == own_ref
  expect read_pool(own_input.output) == pool
  expect script_input_count(self, policy_id) == 1
  expect dict.is_empty(assets.tokens(self.mint, policy_id))
  let output = pool_output(self, policy_id)
  expect
    list.all(
      self.inputs,
      fn(i) {
        i.output_reference == own_ref || dict.is_empty(
          assets.tokens(i.output.value, policy_id),
        )
      },
    )
  expect
    list.all(
      self.outputs,
      fn(out) {
        out == output || dict.is_empty(assets.tokens(out.value, policy_id))
      },
    )
  (policy_id, own_input, output)
}

fn validate_notify_rewards(
  config: PoolConfig,
  pool: PoolDatum,
  reward: Int,
  duration_seconds: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect and {
      reward > 0,
      duration_seconds > 0,
      list.has(self.extra_signatories, config.rewards_distributor),
    }
  let (policy_id, own_input, output) = authenticate_pool_transition(
    config,
    pool,
    own_ref,
    self,
  )
  let time = effective_time_seconds(self)
  let checkpoint = rewards.checkpoint_pool(pool, time)
  let remaining = if pool.period_finish_seconds > time {
    pool.period_finish_seconds - time
  } else {
    0
  }
  let new_rate = ( reward + remaining * pool.reward_rate ) / duration_seconds
  let new_finish = time + duration_seconds
  expect new_finish >= pool.period_finish_seconds
  let expected = PoolDatum {
    ..checkpoint,
    reward_duration_seconds: duration_seconds,
    period_finish_seconds: new_finish,
    reward_rate: new_rate,
    last_update_seconds: time,
  }
  let stake = config.staking_asset
  let rewards_asset = config.reward_asset
  let stake_balance = assets.quantity_of(
    output.value,
    stake.policy_id,
    stake.token_name,
  )
  let reward_balance = assets.quantity_of(
    output.value,
    rewards_asset.policy_id,
    rewards_asset.token_name,
  )
  let principal_in_reward_asset = if stake == rewards_asset {
    pool.total_staked
  } else {
    0
  }
  and {
    read_pool(output) == expected,
    // No reserve, unrelated token or ADA extraction is part of notification.
    list.all(
      assets.flatten(own_input.output.value),
      fn(entry) {
        let (pid, name, quantity) = entry
        assets.quantity_of(output.value, pid, name) >= quantity
      },
    ),
    stake_balance >= pool.total_staked,
    if stake == rewards_asset {
      True
    } else {
      stake_balance == assets.quantity_of(
        own_input.output.value,
        stake.policy_id,
        stake.token_name,
      )
    },
    reward_balance >= principal_in_reward_asset + checkpoint.accrued_liability_bound + new_rate * duration_seconds,
  }
}

// Reserve-only top-up: no checkpoint or emission schedule change.
fn validate_fund_rewards(
  config: PoolConfig,
  pool: PoolDatum,
  amount: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect amount > 0
  expect list.has(self.extra_signatories, config.rewards_distributor)
  let (policy_id, own_input, output) = authenticate_pool_transition(
    config,
    pool,
    own_ref,
    self,
  )
  let stake = config.staking_asset
  let reward_asset = config.reward_asset
  and {
    read_pool(output) == pool,
    assets.quantity_of(
      output.value,
      reward_asset.policy_id,
      reward_asset.token_name,
    ) == assets.quantity_of(
      own_input.output.value,
      reward_asset.policy_id,
      reward_asset.token_name,
    ) + amount,
    if stake == reward_asset {
      True
    } else {
      assets.quantity_of(output.value, stake.policy_id, stake.token_name) == assets.quantity_of(
        own_input.output.value,
        stake.policy_id,
        stake.token_name,
      )
    },
    list.all(
      assets.flatten(own_input.output.value),
      fn(entry) {
        let (pid, name, quantity) = entry
        assets.quantity_of(output.value, pid, name) >= quantity
      },
    ),
  }
}

// Pausing gates deposits only; withdrawals/claims/closures remain available.
fn validate_toggle_pause(
  config: PoolConfig,
  pool: PoolDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_manager_toggle(config, pool, own_ref, self, TogglePause)
}

fn validate_toggle_lock(
  config: PoolConfig,
  pool: PoolDatum,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  validate_manager_toggle(config, pool, own_ref, self, ToggleWithdrawLock)
}

// Both manager controls preserve the exact pool value and change just one flag.
fn validate_manager_toggle(
  config: PoolConfig,
  pool: PoolDatum,
  own_ref: OutputReference,
  self: Transaction,
  action: StakingAction,
) -> Bool {
  let expected = when action is {
    TogglePause -> PoolDatum { ..pool, is_paused: !pool.is_paused }
    ToggleWithdrawLock -> {
      expect !config.vault_supported
      PoolDatum { ..pool, is_locked: !pool.is_locked }
    }
    _ -> fail @"Unsupported manager toggle"
  }
  expect list.has(self.extra_signatories, config.manager)
  let (policy_id, own_input, output) = authenticate_pool_transition(
    config,
    pool,
    own_ref,
    self,
  )
  and {
    read_pool(output) == expected,
    output.value == own_input.output.value,
  }
}

// Recover only native-token surplus; ADA and all protocol identity tokens stay protected.
fn validate_recover_surplus(
  config: PoolConfig,
  pool: PoolDatum,
  asset: AssetClass,
  amount: Int,
  own_ref: OutputReference,
  self: Transaction,
) -> Bool {
  expect amount > 0
  expect list.has(self.extra_signatories, config.manager)
  let (policy_id, own_input, output) = authenticate_pool_transition(
    config,
    pool,
    own_ref,
    self,
  )
  expect valid_asset(asset, policy_id)
  let time = effective_time_seconds(self)
  let checkpoint = rewards.checkpoint_pool(pool, time)
  let remaining = if pool.period_finish_seconds > time {
    pool.period_finish_seconds - time
  } else {
    0
  }
  let stake = config.staking_asset
  let reward = config.reward_asset
  let old_balance = assets.quantity_of(
    own_input.output.value,
    asset.policy_id,
    asset.token_name,
  )
  let paid = list.foldl(
    self.outputs,
    0,
    fn(out, total) {
      if out.address.payment_credential == VerificationKey(config.manager) {
        total + assets.quantity_of(out.value, asset.policy_id, asset.token_name)
      } else {
        total
      }
    },
  )
  and {
    read_pool(output) == checkpoint,
    old_balance >= amount,
    assets.quantity_of(output.value, asset.policy_id, asset.token_name) == old_balance - amount,
    paid >= amount,
    assets.quantity_of(output.value, stake.policy_id, stake.token_name) >= pool.total_staked,
    assets.quantity_of(output.value, reward.policy_id, reward.token_name) >= checkpoint.accrued_liability_bound + remaining * pool.reward_rate + if stake == reward {
      pool.total_staked
    } else {
      0
    },
    list.all(
      assets.flatten(own_input.output.value),
      fn(entry) {
        let (pid, name, quantity) = entry
        let deduction = if pid == asset.policy_id && name == asset.token_name {
          amount
        } else {
          0
        }
        assets.quantity_of(output.value, pid, name) >= quantity - deduction
      },
    ),
  }
}

// Shared accounting helpers use the canonical reward formulas.
pub fn last_time_reward_applicable(pool: PoolDatum, time_seconds: Int) -> Int {
  rewards.last_time_reward_applicable(pool, time_seconds)
}

pub fn checkpoint_pool(pool: PoolDatum, time_seconds: Int) -> PoolDatum {
  rewards.checkpoint_pool(pool, time_seconds)
}

pub fn checkpoint_position(
  position: PositionDatum,
  reward_per_token: Int,
) -> PositionDatum {
  rewards.checkpoint_position(position, reward_per_token)
}

pub fn calculate_earned(position: PositionDatum, reward_per_token: Int) -> Int {
  rewards.calculate_earned(position, reward_per_token)
}

// Ledger intervals are milliseconds; reward accounting uses seconds.
// Use a finite [lower, upper) interval no wider than 60 seconds.
pub fn effective_time_seconds(self: Transaction) -> Int {
  let range = self.validity_range
  expect Finite(lower) = range.lower_bound.bound_type
  expect Finite(upper) = range.upper_bound.bound_type
  expect and {
      range.lower_bound.is_inclusive,
      !range.upper_bound.is_inclusive,
      lower >= 0,
      upper > lower,
      upper - lower <= 60_000,
    }
  lower / 1000
}

// Identity-mint fixtures; complete staking transitions have separate handler/transaction tests.
const fixture_manager =
  #"11111111111111111111111111111111111111111111111111111111"

const fixture_policy =
  #"22222222222222222222222222222222222222222222222222222222"

// Synthetic trust anchor used only by unit fixtures; no deployed factory is selected.
const fixture_factory_policy =
  #"55555555555555555555555555555555555555555555555555555555"

const fixture_asset_policy =
  #"33333333333333333333333333333333333333333333333333333333"

fn fixture_ref(index: Int) -> OutputReference {
  OutputReference {
    transaction_id: transaction.placeholder.id,
    output_index: index,
  }
}

fn fixture_config() -> PoolConfig {
  PoolConfig {
    bootstrap_ref: fixture_ref(0),
    manager: fixture_manager,
    rewards_distributor: fixture_manager,
    staking_asset: AssetClass {
      policy_id: fixture_asset_policy,
      token_name: #"41",
    },
    reward_asset: AssetClass {
      policy_id: fixture_asset_policy,
      token_name: #"42",
    },
    initially_locked: True,
    vault_supported: False,
    factory_policy: None,
  }
}

fn fixture_pool() -> PoolDatum {
  PoolDatum {
    total_staked: 0,
    reward_duration_seconds: 0,
    period_finish_seconds: 0,
    reward_rate: 0,
    last_update_seconds: 0,
    reward_per_token_stored: 0,
    accrued_liability_bound: 0,
    is_paused: False,
    is_locked: True,
  }
}

fn fixture_output(name: AssetName, state: StakingDatum) -> Output {
  let data: Data = state
  Output {
    address: address.from_script(fixture_policy),
    value: assets.from_asset(fixture_policy, name, 1)
      |> assets.add(#"", #"", 2_000_000),
    datum: InlineDatum(data),
    reference_script: None,
  }
}

fn fixture_init() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: fixture_ref(0),
        output: Output {
          ..fixture_output(pool_token_name, Pool(fixture_pool())),
          address: address.from_verification_key(fixture_manager),
          value: assets.from_lovelace(10_000_000),
        },
      },
    ],
    outputs: [fixture_output(pool_token_name, Pool(fixture_pool()))],
    mint: assets.from_asset(fixture_policy, pool_token_name, 1),
    extra_signatories: [fixture_manager],
  }
}

fn fixture_validate(action: IdentityAction, self: Transaction) -> Bool {
  let config = fixture_config()
  single_staking.mint(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    action,
    fixture_policy,
    self,
  )
}

fn fixture_open() -> Transaction {
  let creation_ref = fixture_ref(2)
  let name = position_token_name(creation_ref)
  let action: Data = Stake {
    amount: 100,
    position_id: name,
    creation_ref: Some(creation_ref),
  }
  let before = fixture_output(pool_token_name, Pool(fixture_pool()))
  let after = Output {
    ..fixture_output(
      pool_token_name,
      Pool(PoolDatum { ..fixture_pool(), total_staked: 100 }),
    ),
    value: before.value |> assets.add(fixture_asset_policy, #"41", 100),
  }
  let position = PositionDatum {
    schema_version: position_schema_version,
    pool_id: fixture_policy,
    position_name: name,
    owner: WalletOwner(fixture_manager),
    payout_address: address.from_verification_key(fixture_manager),
    staked_amount: 100,
    reward_per_token_paid: 0,
    pending_rewards: 0,
  }
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input { output_reference: fixture_ref(1), output: before },
      fixture_init().inputs
        |> list.expect_head
        |> fn(i) { Input { ..i, output_reference: creation_ref } },
    ],
    outputs: [after, fixture_output(name, Position(position))],
    mint: assets.from_asset(fixture_policy, name, 1),
    extra_signatories: [fixture_manager],
    redeemers: [Pair(Spend(fixture_ref(1)), action)],
  }
}

fn fixture_close(empty: Bool) -> Transaction {
  let open = fixture_open()
  expect [pool_out, position_out] = open.outputs
  let position = read_position(position_out)
  let name = position.position_name
  let action: StakingAction = if empty {
    CloseEmptyPosition { position_id: name }
  } else {
    Exit { position_id: name }
  }
  let action_data: Data = action
  let position_out = if empty {
    fixture_output(
      name,
      Position(PositionDatum { ..position, staked_amount: 0 }),
    )
  } else {
    position_out
  }
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input { output_reference: fixture_ref(3), output: pool_out },
      Input { output_reference: fixture_ref(4), output: position_out },
    ],
    outputs: [
      fixture_output(
        pool_token_name,
        Pool(
          PoolDatum {
            ..fixture_pool(),
            total_staked: if empty {
              100
            } else {
              0
            },
          },
        ),
      ),
    ],
    mint: assets.from_asset(fixture_policy, name, -1),
    extra_signatories: [fixture_manager],
    redeemers: [
      Pair(Spend(fixture_ref(3)), action_data),
      Pair(Spend(fixture_ref(4)), action_data),
    ],
  }
}

test initialize_pool_succeeds() {
  fixture_validate(InitializePool, fixture_init())
}

test initialize_requires_manager() fail {
  fixture_validate(
    InitializePool,
    Transaction { ..fixture_init(), extra_signatories: [] },
  )
}

test initialize_requires_consumed_bootstrap() fail {
  let tx = fixture_init()
  fixture_validate(
    InitializePool,
    Transaction { ..tx, inputs: [], reference_inputs: tx.inputs },
  )
}

test initialize_rejects_forged_starting_balance() {
  !fixture_validate(
    InitializePool,
    Transaction {
      ..fixture_init(),
      outputs: [
        fixture_output(
          pool_token_name,
          Pool(PoolDatum { ..fixture_pool(), total_staked: 100 }),
        ),
      ],
    },
  )
}

test initialize_rejects_incorrect_lock() {
  !fixture_validate(
    InitializePool,
    Transaction {
      ..fixture_init(),
      outputs: [
        fixture_output(
          pool_token_name,
          Pool(PoolDatum { ..fixture_pool(), is_locked: False }),
        ),
      ],
    },
  )
}

test initialize_rejects_wrong_address() fail {
  expect [output] = fixture_init().outputs
  fixture_validate(
    InitializePool,
    Transaction {
      ..fixture_init(),
      outputs: [
        Output {
          ..output,
          address: address.from_verification_key(fixture_manager),
        },
      ],
    },
  )
}

test initialize_rejects_extra_protocol_mint() fail {
  fixture_validate(
    InitializePool,
    Transaction {
      ..fixture_init(),
      mint: fixture_init().mint |> assets.add(fixture_policy, #"4558545241", 1),
    },
  )
}

test initialize_rejects_own_protocol_staking_asset() fail {
  let config = fixture_config()
  validate_initialize_pool(
    PoolConfig {
      ..config,
      staking_asset: AssetClass {
        policy_id: fixture_policy,
        token_name: pool_token_name,
      },
    },
    fixture_policy,
    fixture_init(),
  )
}

test initialize_rejects_reused_protocol_state() fail {
  fixture_validate(
    InitializePool,
    Transaction { ..fixture_init(), inputs: fixture_open().inputs },
  )
}

test position_names_are_unique_by_output_reference() {
  position_token_name(fixture_ref(1)) != position_token_name(fixture_ref(2))
}

test open_position_succeeds_with_matching_pool_stake() {
  fixture_validate(
    OpenPosition {
      schema_version: position_schema_version,
      creation_ref: fixture_ref(2),
      owner: WalletOwner(fixture_manager),
    },
    fixture_open(),
  )
}

test open_position_requires_owner() fail {
  fixture_validate(
    OpenPosition {
      schema_version: position_schema_version,
      creation_ref: fixture_ref(2),
      owner: WalletOwner(fixture_manager),
    },
    Transaction { ..fixture_open(), extra_signatories: [] },
  )
}

test open_position_requires_pool_spend_redeemer() fail {
  fixture_validate(
    OpenPosition {
      schema_version: position_schema_version,
      creation_ref: fixture_ref(2),
      owner: WalletOwner(fixture_manager),
    },
    Transaction { ..fixture_open(), redeemers: [] },
  )
}

test open_position_rejects_prior_rewards() {
  let tx = fixture_open()
  expect [pool_out, position_out] = tx.outputs
  let position = read_position(position_out)
  !fixture_validate(
    OpenPosition {
      schema_version: position_schema_version,
      creation_ref: fixture_ref(2),
      owner: WalletOwner(fixture_manager),
    },
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        fixture_output(
          position.position_name,
          Position(PositionDatum { ..position, pending_rewards: 50 }),
        ),
      ],
    },
  )
}

test close_position_exit_succeeds() {
  fixture_validate(
    ClosePosition { position_id: position_token_name(fixture_ref(2)) },
    fixture_close(False),
  )
}

test close_empty_position_succeeds() {
  fixture_validate(
    ClosePosition { position_id: position_token_name(fixture_ref(2)) },
    fixture_close(True),
  )
}

test close_position_requires_owner() fail {
  fixture_validate(
    ClosePosition { position_id: position_token_name(fixture_ref(2)) },
    Transaction { ..fixture_close(False), extra_signatories: [] },
  )
}

test close_position_requires_matching_position_redeemer() fail {
  let tx = fixture_close(False)
  let wrong: Data = Claim { position_id: position_token_name(fixture_ref(2)) }
  fixture_validate(
    ClosePosition { position_id: position_token_name(fixture_ref(2)) },
    Transaction {
      ..tx,
      redeemers: [
        list.expect_head(tx.redeemers),
        Pair(Spend(fixture_ref(4)), wrong),
      ],
    },
  )
}

test pool_nft_cannot_be_burned() fail {
  fixture_validate(
    ClosePosition { position_id: pool_token_name },
    fixture_init(),
  )
}

// NotifyRewards fixtures invoke the actual spending handler.
const fixture_distributor =
  #"55555555555555555555555555555555555555555555555555555555"

fn notify_config() -> PoolConfig {
  PoolConfig { ..fixture_config(), rewards_distributor: fixture_distributor }
}

fn notify_range(lower: Int, upper: Int) -> Interval {
  Interval {
    lower_bound: IntervalBound { bound_type: Finite(lower), is_inclusive: True },
    upper_bound: IntervalBound {
      bound_type: Finite(upper),
      is_inclusive: False,
    },
  }
}

fn notify_fixture(active: Bool) -> Transaction {
  let initial = PoolDatum { ..fixture_pool(), total_staked: 1000 }
  let before = if active {
    PoolDatum {
      ..initial,
      reward_rate: 10,
      reward_duration_seconds: 600,
      period_finish_seconds: 700,
      last_update_seconds: 100,
    }
  } else {
    initial
  }
  let after = if active {
    PoolDatum {
      ..before,
      reward_rate: 14,
      reward_duration_seconds: 600,
      period_finish_seconds: 760,
      last_update_seconds: 160,
      reward_per_token_stored: 600_000_000_000_000_000,
      accrued_liability_bound: 600,
    }
  } else {
    PoolDatum {
      ..before,
      reward_rate: 10,
      reward_duration_seconds: 600,
      period_finish_seconds: 700,
      last_update_seconds: 100,
    }
  }
  let input = fixture_output(pool_token_name, Pool(before))
  let output = fixture_output(pool_token_name, Pool(after))
  let action: Data = NotifyRewards {
    reward: if active {
      3000
    } else {
      6000
    },
    duration_seconds: 600,
  }
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: fixture_ref(8),
        output: Output {
          ..input,
          value: input.value
            |> assets.add(fixture_asset_policy, #"41", 1000)
            |> assets.add(
                fixture_asset_policy,
                #"42",
                if active {
                  6000
                } else {
                  0
                },
              ),
        },
      },
    ],
    outputs: [
      Output {
        ..output,
        value: output.value
          |> assets.add(fixture_asset_policy, #"41", 1000)
          |> assets.add(
              fixture_asset_policy,
              #"42",
              if active {
                9000
              } else {
                6000
              },
            ),
      },
    ],
    extra_signatories: [fixture_distributor],
    validity_range: notify_range(
      if active {
        160_000
      } else {
        100_000
      },
      if active {
        190_000
      } else {
        130_000
      },
    ),
    redeemers: [Pair(Spend(fixture_ref(8)), action)],
  }
}

fn notify_validate(
  config: PoolConfig,
  reward: Int,
  duration: Int,
  tx: Transaction,
) -> Bool {
  let input = list.expect_head(tx.inputs)
  let datum = Pool(read_pool(input.output))
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(datum),
    NotifyRewards { reward, duration_seconds: duration },
    fixture_ref(8),
    tx,
  )
}

test notify_starts_funded_schedule() {
  notify_validate(notify_config(), 6000, 600, notify_fixture(False))
}

test notify_active_schedule_includes_leftover_and_liability() {
  // 60s * 10 = 600 accrued; 540s * 10 = 5400 leftover.
  // (3000 + 5400) / 600 = 14/sec; reserve 9000 = 600 owed + 8400 future.
  notify_validate(notify_config(), 3000, 600, notify_fixture(True))
}

test notify_manager_is_not_distributor() fail {
  notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..notify_fixture(False),
      extra_signatories: [fixture_manager],
    },
  )
}

test notify_zero_duration_rejected() fail {
  notify_validate(notify_config(), 6000, 0, notify_fixture(False))
}

test notify_zero_reward_rejected() fail {
  notify_validate(notify_config(), 0, 600, notify_fixture(False))
}

test notify_cannot_shorten_active_period() fail {
  notify_validate(notify_config(), 3000, 10, notify_fixture(True))
}

test notify_insufficient_reserve_rejected() {
  let tx = notify_fixture(False)
  let output = list.expect_head(tx.outputs)
  !notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..output,
          value: output.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
      ],
    },
  )
}

test notify_cannot_extract_surplus() {
  let tx = notify_fixture(False)
  let input = list.expect_head(tx.inputs)
  !notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..tx,
      inputs: [
        Input {
          ..input,
          output: Output {
            ..input.output,
            value: input.output.value
              |> assets.add(fixture_asset_policy, #"42", 10_000),
          },
        },
      ],
    },
  )
}

test notify_tampered_finish_rejected() {
  let tx = notify_fixture(False)
  let output = list.expect_head(tx.outputs)
  let state: Data = Pool(
    PoolDatum { ..read_pool(output), period_finish_seconds: 800 },
  )
  !notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..tx,
      outputs: [Output { ..output, datum: InlineDatum(state) }],
    },
  )
}

test notify_tampered_principal_rejected() {
  let tx = notify_fixture(False)
  let output = list.expect_head(tx.outputs)
  let state: Data = Pool(PoolDatum { ..read_pool(output), total_staked: 999 })
  !notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..tx,
      outputs: [Output { ..output, datum: InlineDatum(state) }],
    },
  )
}

test notify_unbounded_time_rejected() fail {
  notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..notify_fixture(False),
      validity_range: transaction.placeholder.validity_range,
    },
  )
}

test notify_overwide_time_rejected() fail {
  notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..notify_fixture(False),
      validity_range: notify_range(100_000, 160_001),
    },
  )
}

test notify_backward_time_rejected() fail {
  notify_validate(
    notify_config(),
    3000,
    600,
    Transaction {
      ..notify_fixture(True),
      validity_range: notify_range(99_000, 100_000),
    },
  )
}

test notify_protocol_mint_rejected() fail {
  notify_validate(
    notify_config(),
    6000,
    600,
    Transaction {
      ..notify_fixture(False),
      mint: assets.from_asset(fixture_policy, #"424144", 1),
    },
  )
}

fn same_asset_notify(reserve: Int) -> Bool {
  let config = notify_config()
  let tx = notify_fixture(False)
  let output = list.expect_head(tx.outputs)
  let value = assets.from_asset(fixture_policy, pool_token_name, 1)
    |> assets.add(#"", #"", 2_000_000)
    |> assets.add(fixture_asset_policy, #"41", reserve)
  notify_validate(
    PoolConfig { ..config, reward_asset: config.staking_asset },
    6000,
    600,
    Transaction { ..tx, outputs: [Output { ..output, value }] },
  )
}

test notify_same_asset_covers_principal_and_rewards() {
  same_asset_notify(7000)
}

test notify_same_asset_cannot_count_principal_as_rewards() {
  !same_asset_notify(6000)
}

// Stake-spend tests, including state forgery and value-extraction attempts.
fn stake_validate(
  amount: Int,
  creation: Option<OutputReference>,
  tx: Transaction,
) -> Bool {
  let config = fixture_config()
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    Stake {
      amount,
      position_id: position_token_name(fixture_ref(2)),
      creation_ref: creation,
    },
    input.output_reference,
    tx,
  )
}

fn stake_new_fixture() -> Transaction {
  Transaction {
    ..fixture_open(),
    validity_range: notify_range(100_000, 130_000),
  }
}

fn stake_topup_fixture() -> Transaction {
  let open = fixture_open()
  expect [pool_out, position_out] = open.outputs
  let before = PoolDatum {
    ..read_pool(pool_out),
    reward_rate: 10,
    reward_duration_seconds: 600,
    period_finish_seconds: 600,
    last_update_seconds: 100,
  }
  let after = PoolDatum {
    ..before,
    total_staked: 150,
    last_update_seconds: 160,
    reward_per_token_stored: 6_000_000_000_000_000_000,
    accrued_liability_bound: 600,
  }
  let previous = read_position(position_out)
  let next = PositionDatum {
    ..previous,
    staked_amount: 150,
    reward_per_token_paid: 6_000_000_000_000_000_000,
    pending_rewards: 600,
  }
  let input_pool = fixture_output(pool_token_name, Pool(before))
  let output_pool = fixture_output(pool_token_name, Pool(after))
  let action: Data = Stake {
    amount: 50,
    position_id: previous.position_name,
    creation_ref: None,
  }
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: fixture_ref(3),
        output: Output {
          ..input_pool,
          value: input_pool.value
            |> assets.add(fixture_asset_policy, #"41", 100)
            |> assets.add(fixture_asset_policy, #"42", 6000),
        },
      },
      Input { output_reference: fixture_ref(4), output: position_out },
    ],
    outputs: [
      Output {
        ..output_pool,
        value: output_pool.value
          |> assets.add(fixture_asset_policy, #"41", 150)
          |> assets.add(fixture_asset_policy, #"42", 6000),
      },
      fixture_output(previous.position_name, Position(next)),
    ],
    extra_signatories: [fixture_manager],
    validity_range: notify_range(160_000, 190_000),
    redeemers: [
      Pair(Spend(fixture_ref(3)), action),
      Pair(Spend(fixture_ref(4)), action),
    ],
  }
}

test stake_first_deposit_succeeds() {
  stake_validate(100, Some(fixture_ref(2)), stake_new_fixture())
}

test stake_topup_checkpoints_previous_balance() {
  stake_validate(50, None, stake_topup_fixture())
}

test stake_position_spend_checks_matching_pool_transition() {
  let tx = stake_topup_fixture()
  expect [_, position_input] = tx.inputs
  let config = fixture_config()
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Position(read_position(position_input.output))),
    Stake {
      amount: 50,
      position_id: position_token_name(fixture_ref(2)),
      creation_ref: None,
    },
    position_input.output_reference,
    tx,
  )
}

test stake_requires_owner_signature() fail {
  stake_validate(
    100,
    Some(fixture_ref(2)),
    Transaction { ..stake_new_fixture(), extra_signatories: [] },
  )
}

test stake_zero_amount_rejected() fail {
  stake_validate(0, Some(fixture_ref(2)), stake_new_fixture())
}

test stake_negative_amount_rejected() fail {
  stake_validate(-1, Some(fixture_ref(2)), stake_new_fixture())
}

test stake_paused_pool_rejected() fail {
  let tx = stake_new_fixture()
  expect [pool_in, seed] = tx.inputs
  stake_validate(
    100,
    Some(fixture_ref(2)),
    Transaction {
      ..tx,
      inputs: [
        Input {
          ..pool_in,
          output: fixture_output(
            pool_token_name,
            Pool(PoolDatum { ..fixture_pool(), is_paused: True }),
          ),
        },
        seed,
      ],
    },
  )
}

test stake_requires_actual_principal_deposit() {
  let tx = stake_new_fixture()
  expect [pool_out, position_out] = tx.outputs
  !stake_validate(
    100,
    Some(fixture_ref(2)),
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..pool_out,
          value: pool_out.value |> assets.add(fixture_asset_policy, #"41", -1),
        },
        position_out,
      ],
    },
  )
}

test stake_cannot_change_pool_schedule() fail {
  let tx = stake_new_fixture()
  expect [pool_out, position_out] = tx.outputs
  let raw: Data = Pool(
    PoolDatum { ..read_pool(pool_out), period_finish_seconds: 1000 },
  )
  stake_validate(
    100,
    Some(fixture_ref(2)),
    Transaction {
      ..tx,
      outputs: [Output { ..pool_out, datum: InlineDatum(raw) }, position_out],
    },
  )
}

test stake_cannot_claim_old_rewards_on_new_position() fail {
  let tx = stake_new_fixture()
  expect [pool_out, position_out] = tx.outputs
  let position = read_position(position_out)
  let raw: Data = Position(PositionDatum { ..position, pending_rewards: 999 })
  stake_validate(
    100,
    Some(fixture_ref(2)),
    Transaction {
      ..tx,
      outputs: [pool_out, Output { ..position_out, datum: InlineDatum(raw) }],
    },
  )
}

test stake_cannot_reset_pending_rewards_on_topup() fail {
  let tx = stake_topup_fixture()
  expect [pool_out, position_out] = tx.outputs
  let raw: Data = Position(
    PositionDatum { ..read_position(position_out), pending_rewards: 0 },
  )
  stake_validate(
    50,
    None,
    Transaction {
      ..tx,
      outputs: [pool_out, Output { ..position_out, datum: InlineDatum(raw) }],
    },
  )
}

test stake_cannot_change_payout_on_topup() fail {
  let tx = stake_topup_fixture()
  expect [pool_out, position_out] = tx.outputs
  let raw: Data = Position(
    PositionDatum {
      ..read_position(position_out),
      payout_address: address.from_verification_key(fixture_distributor),
    },
  )
  stake_validate(
    50,
    None,
    Transaction {
      ..tx,
      outputs: [pool_out, Output { ..position_out, datum: InlineDatum(raw) }],
    },
  )
}

test stake_cannot_extract_reward_reserves() {
  let tx = stake_topup_fixture()
  expect [pool_out, position_out] = tx.outputs
  !stake_validate(
    50,
    None,
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..pool_out,
          value: pool_out.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
        position_out,
      ],
    },
  )
}

test stake_cannot_remint_position_on_topup() fail {
  stake_validate(
    50,
    None,
    Transaction {
      ..stake_topup_fixture(),
      mint: assets.from_asset(
        fixture_policy,
        position_token_name(fixture_ref(2)),
        1,
      ),
    },
  )
}

test stake_topup_requires_matching_position_action() fail {
  let tx = stake_topup_fixture()
  let wrong: Data = Claim { position_id: position_token_name(fixture_ref(2)) }
  stake_validate(
    50,
    None,
    Transaction {
      ..tx,
      redeemers: [
        list.expect_head(tx.redeemers),
        Pair(Spend(fixture_ref(4)), wrong),
      ],
    },
  )
}

fn withdraw_fixture(amount: Int, locked: Bool, time: Int) -> Transaction {
  let base = stake_topup_fixture()
  expect [pool_in, position_in] = base.inputs
  let before = PoolDatum { ..read_pool(pool_in.output), is_locked: locked }
  let checkpoint = rewards.checkpoint_pool(before, time)
  let previous = read_position(position_in.output)
  let accrued = rewards.checkpoint_position(
    previous,
    checkpoint.reward_per_token_stored,
  )
  let after = PoolDatum {
    ..checkpoint,
    total_staked: before.total_staked - amount,
  }
  let next = PositionDatum {
    ..accrued,
    staked_amount: previous.staked_amount - amount,
  }
  let input_data: Data = Pool(before)
  let output_data: Data = Pool(after)
  let position_data: Data = Position(next)
  let action: Data = Withdraw { amount, position_id: previous.position_name }
  Transaction {
    ..base,
    inputs: [
      Input {
        ..pool_in,
        output: Output { ..pool_in.output, datum: InlineDatum(input_data) },
      },
      position_in,
    ],
    outputs: [
      Output {
        ..pool_in.output,
        datum: InlineDatum(output_data),
        value: pool_in.output.value
          |> assets.add(fixture_asset_policy, #"41", -amount),
      },
      Output { ..position_in.output, datum: InlineDatum(position_data) },
      Output {
        address: previous.payout_address,
        value: assets.from_asset(fixture_asset_policy, #"41", amount)
          |> assets.add(#"", #"", 2_000_000),
        datum: transaction.NoDatum,
        reference_script: None,
      },
    ],
    validity_range: notify_range(time * 1000, ( time + 30 ) * 1000),
    redeemers: [
      Pair(Spend(fixture_ref(3)), action),
      Pair(Spend(fixture_ref(4)), action),
    ],
  }
}

fn withdraw_validate(amount: Int, tx: Transaction) -> Bool {
  let config = fixture_config()
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    Withdraw { amount, position_id: position_token_name(fixture_ref(2)) },
    input.output_reference,
    tx,
  )
}

test withdraw_partial_unlocked_succeeds() {
  withdraw_validate(40, withdraw_fixture(40, False, 160))
}

test withdraw_full_preserves_position_and_pending_rewards() {
  let tx = withdraw_fixture(100, False, 160)
  expect [_, position_out, _] = tx.outputs
  and {
    withdraw_validate(100, tx),
    read_position(position_out).staked_amount == 0,
    read_position(position_out).pending_rewards == 600,
  }
}

test withdraw_position_handler_checks_pool_transition() {
  let tx = withdraw_fixture(40, False, 160)
  expect [_, position_in] = tx.inputs
  let config = fixture_config()
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Position(read_position(position_in.output))),
    Withdraw { amount: 40, position_id: position_token_name(fixture_ref(2)) },
    position_in.output_reference,
    tx,
  )
}

test withdraw_locked_before_finish_fails() fail {
  withdraw_validate(40, withdraw_fixture(40, True, 160))
}

test withdraw_locked_at_finish_fails() fail {
  withdraw_validate(40, withdraw_fixture(40, True, 600))
}

test withdraw_locked_after_finish_succeeds() {
  withdraw_validate(40, withdraw_fixture(40, True, 601))
}

test withdraw_interval_crossing_deadline_fails() fail {
  withdraw_validate(
    40,
    Transaction {
      ..withdraw_fixture(40, True, 599),
      validity_range: notify_range(599_000, 620_000),
    },
  )
}

test withdraw_requires_owner() fail {
  withdraw_validate(
    40,
    Transaction {
      ..withdraw_fixture(40, False, 160),
      extra_signatories: [fixture_distributor],
    },
  )
}

test withdraw_zero_fails() fail {
  withdraw_validate(0, withdraw_fixture(0, False, 160))
}

test withdraw_excess_fails() fail {
  withdraw_validate(101, withdraw_fixture(101, False, 160))
}

test withdraw_does_not_pay_another_address() {
  let tx = withdraw_fixture(40, False, 160)
  expect [pool_out, position_out, payout] = tx.outputs
  !withdraw_validate(
    40,
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        position_out,
        Output {
          ..payout,
          address: address.from_verification_key(fixture_distributor),
        },
      ],
    },
  )
}

test withdraw_cannot_clear_unclaimed_rewards() fail {
  let tx = withdraw_fixture(40, False, 160)
  expect [pool_out, position_out, payout] = tx.outputs
  let data: Data = Position(
    PositionDatum { ..read_position(position_out), pending_rewards: 0 },
  )
  withdraw_validate(
    40,
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output { ..position_out, datum: InlineDatum(data) },
        payout,
      ],
    },
  )
}

test withdraw_cannot_extract_reward_reserve() {
  let tx = withdraw_fixture(40, False, 160)
  expect [pool_out, position_out, payout] = tx.outputs
  !withdraw_validate(
    40,
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..pool_out,
          value: pool_out.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
        position_out,
        payout,
      ],
    },
  )
}

test withdraw_cannot_burn_position() fail {
  withdraw_validate(
    40,
    Transaction {
      ..withdraw_fixture(40, False, 160),
      mint: assets.from_asset(
        fixture_policy,
        position_token_name(fixture_ref(2)),
        -1,
      ),
    },
  )
}

test withdraw_requires_matching_position_redeemer() fail {
  let tx = withdraw_fixture(40, False, 160)
  let wrong: Data = Withdraw {
    amount: 41,
    position_id: position_token_name(fixture_ref(2)),
  }
  withdraw_validate(
    40,
    Transaction {
      ..tx,
      redeemers: [
        list.expect_head(tx.redeemers),
        Pair(Spend(fixture_ref(4)), wrong),
      ],
    },
  )
}

test withdraw_allowed_while_paused() {
  let tx = withdraw_fixture(40, False, 160)
  expect [pool_in, position_in] = tx.inputs
  expect [pool_out, position_out, payout] = tx.outputs
  let before: Data = Pool(
    PoolDatum { ..read_pool(pool_in.output), is_paused: True },
  )
  let after: Data = Pool(PoolDatum { ..read_pool(pool_out), is_paused: True })
  withdraw_validate(
    40,
    Transaction {
      ..tx,
      inputs: [
        Input {
          ..pool_in,
          output: Output { ..pool_in.output, datum: InlineDatum(before) },
        },
        position_in,
      ],
      outputs: [
        Output { ..pool_out, datum: InlineDatum(after) },
        position_out,
        payout,
      ],
    },
  )
}

fn same_asset_withdraw(extra_reduction: Int) -> Bool {
  let tx = withdraw_fixture(40, False, 160)
  expect [pool_in, position_in] = tx.inputs
  expect [pool_out, position_out, payout] = tx.outputs
  let input_value = pool_in.output.value
    |> assets.add(fixture_asset_policy, #"42", -6000)
    |> assets.add(fixture_asset_policy, #"41", 6000)
  let output_value = pool_out.value
    |> assets.add(fixture_asset_policy, #"42", -6000)
    |> assets.add(fixture_asset_policy, #"41", 6000 - extra_reduction)
  let config = fixture_config()
  let adjusted_config = PoolConfig {
    ..config,
    reward_asset: config.staking_asset,
  }
  let updated = Transaction {
    ..tx,
    inputs: [
      Input {
        ..pool_in,
        output: Output { ..pool_in.output, value: input_value },
      },
      position_in,
    ],
    outputs: [Output { ..pool_out, value: output_value }, position_out, payout],
  }
  single_staking.spend(
    adjusted_config.bootstrap_ref,
    adjusted_config.manager,
    adjusted_config.rewards_distributor,
    adjusted_config.staking_asset,
    adjusted_config.reward_asset,
    adjusted_config.initially_locked,
    adjusted_config.vault_supported,
    adjusted_config.factory_policy,
    Some(Pool(read_pool(pool_in.output))),
    Withdraw { amount: 40, position_id: position_token_name(fixture_ref(2)) },
    pool_in.output_reference,
    updated,
  )
}

test withdraw_same_asset_preserves_reward_backing() {
  same_asset_withdraw(0)
}

test withdraw_same_asset_cannot_remove_extra_reward_units() {
  !same_asset_withdraw(1)
}

fn claim_fixture(time: Int) -> Transaction {
  let base = stake_topup_fixture()
  expect [pool_in, position_in] = base.inputs
  let checkpoint = rewards.checkpoint_pool(read_pool(pool_in.output), time)
  let previous = read_position(position_in.output)
  let accrued = rewards.checkpoint_position(
    previous,
    checkpoint.reward_per_token_stored,
  )
  let reward = accrued.pending_rewards
  let output_pool: Data = Pool(
    PoolDatum {
      ..checkpoint,
      accrued_liability_bound: checkpoint.accrued_liability_bound - reward,
    },
  )
  let output_position: Data = Position(
    PositionDatum { ..accrued, pending_rewards: 0 },
  )
  let action: Data = Claim { position_id: previous.position_name }
  Transaction {
    ..base,
    outputs: [
      Output {
        ..pool_in.output,
        datum: InlineDatum(output_pool),
        value: pool_in.output.value
          |> assets.add(fixture_asset_policy, #"42", -reward),
      },
      Output { ..position_in.output, datum: InlineDatum(output_position) },
      Output {
        address: previous.payout_address,
        value: assets.from_asset(fixture_asset_policy, #"42", reward)
          |> assets.add(#"", #"", 2_000_000),
        datum: transaction.NoDatum,
        reference_script: None,
      },
    ],
    validity_range: notify_range(time * 1000, ( time + 30 ) * 1000),
    redeemers: [
      Pair(Spend(fixture_ref(3)), action),
      Pair(Spend(fixture_ref(4)), action),
    ],
  }
}

fn claim_validate(tx: Transaction) -> Bool {
  let config = fixture_config()
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    Claim { position_id: position_token_name(fixture_ref(2)) },
    input.output_reference,
    tx,
  )
}

test claim_pays_earned_rewards_while_locked() {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  and {
    claim_validate(tx),
    read_pool(pool_out).total_staked == 100,
    read_position(position_out).staked_amount == 100,
    read_position(position_out).pending_rewards == 0,
    assets.quantity_of(payout.value, fixture_asset_policy, #"42") == 600,
  }
}

test claim_zero_rewards_allowed() {
  claim_validate(claim_fixture(100))
}

test claim_caps_rewards_at_period_finish() {
  let tx = claim_fixture(700)
  expect [pool_out, _, payout] = tx.outputs
  and {
    claim_validate(tx),
    read_pool(pool_out).last_update_seconds == 600,
    assets.quantity_of(payout.value, fixture_asset_policy, #"42") == 5000,
  }
}

test claim_position_handler_checks_pool_transition() {
  let tx = claim_fixture(160)
  expect [_, input] = tx.inputs
  let config = fixture_config()
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Position(read_position(input.output))),
    Claim { position_id: position_token_name(fixture_ref(2)) },
    input.output_reference,
    tx,
  )
}

test claim_requires_owner_signature() fail {
  claim_validate(
    Transaction {
      ..claim_fixture(160),
      extra_signatories: [fixture_distributor],
    },
  )
}

test claim_cannot_pay_another_address() {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  !claim_validate(
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        position_out,
        Output {
          ..payout,
          address: address.from_verification_key(fixture_distributor),
        },
      ],
    },
  )
}

test claim_cannot_overpay_from_vault() {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  !claim_validate(
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..pool_out,
          value: pool_out.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
        position_out,
        Output {
          ..payout,
          value: payout.value |> assets.add(fixture_asset_policy, #"42", 1),
        },
      ],
    },
  )
}

test claim_cannot_underpay_owner() {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  !claim_validate(
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        position_out,
        Output {
          ..payout,
          value: payout.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
      ],
    },
  )
}

test claim_cannot_keep_old_paid_checkpoint() fail {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  let data: Data = Position(
    PositionDatum { ..read_position(position_out), reward_per_token_paid: 0 },
  )
  claim_validate(
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output { ..position_out, datum: InlineDatum(data) },
        payout,
      ],
    },
  )
}

test claim_cannot_keep_pending_rewards_for_reclaim() fail {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  let data: Data = Position(
    PositionDatum { ..read_position(position_out), pending_rewards: 600 },
  )
  claim_validate(
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output { ..position_out, datum: InlineDatum(data) },
        payout,
      ],
    },
  )
}

test claim_cannot_spend_principal() {
  let tx = claim_fixture(160)
  expect [pool_out, position_out, payout] = tx.outputs
  !claim_validate(
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..pool_out,
          value: pool_out.value |> assets.add(fixture_asset_policy, #"41", -1),
        },
        position_out,
        payout,
      ],
    },
  )
}

test claim_cannot_burn_position_marker() fail {
  claim_validate(
    Transaction {
      ..claim_fixture(160),
      mint: assets.from_asset(
        fixture_policy,
        position_token_name(fixture_ref(2)),
        -1,
      ),
    },
  )
}

test claim_requires_matching_position_action() fail {
  let tx = claim_fixture(160)
  let wrong: Data = Withdraw {
    amount: 1,
    position_id: position_token_name(fixture_ref(2)),
  }
  claim_validate(
    Transaction {
      ..tx,
      redeemers: [
        list.expect_head(tx.redeemers),
        Pair(Spend(fixture_ref(4)), wrong),
      ],
    },
  )
}

test claim_allowed_while_paused() {
  let tx = claim_fixture(160)
  expect [pool_in, position_in] = tx.inputs
  expect [pool_out, position_out, payout] = tx.outputs
  let before: Data = Pool(
    PoolDatum { ..read_pool(pool_in.output), is_paused: True },
  )
  let after: Data = Pool(PoolDatum { ..read_pool(pool_out), is_paused: True })
  claim_validate(
    Transaction {
      ..tx,
      inputs: [
        Input {
          ..pool_in,
          output: Output { ..pool_in.output, datum: InlineDatum(before) },
        },
        position_in,
      ],
      outputs: [
        Output { ..pool_out, datum: InlineDatum(after) },
        position_out,
        payout,
      ],
    },
  )
}

fn same_asset_claim(extra: Int) -> Bool {
  let tx = claim_fixture(160)
  expect [pool_in, position_in] = tx.inputs
  expect [pool_out, position_out, payout] = tx.outputs
  let input_value = pool_in.output.value
    |> assets.add(fixture_asset_policy, #"42", -6000)
    |> assets.add(fixture_asset_policy, #"41", 6000)
  let output_value = pool_out.value
    |> assets.add(fixture_asset_policy, #"42", -5400)
    |> assets.add(fixture_asset_policy, #"41", 5400 - extra)
  let payout_value = assets.from_asset(fixture_asset_policy, #"41", 600 + extra)
    |> assets.add(#"", #"", 2_000_000)
  let config = fixture_config()
  let updated = Transaction {
    ..tx,
    inputs: [
      Input {
        ..pool_in,
        output: Output { ..pool_in.output, value: input_value },
      },
      position_in,
    ],
    outputs: [
      Output { ..pool_out, value: output_value },
      position_out,
      Output { ..payout, value: payout_value },
    ],
  }
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.staking_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(pool_in.output))),
    Claim { position_id: position_token_name(fixture_ref(2)) },
    pool_in.output_reference,
    updated,
  )
}

test claim_same_asset_preserves_principal_and_future_rewards() {
  same_asset_claim(0)
}

test claim_same_asset_cannot_overpay() {
  !same_asset_claim(1)
}

// Closure fixtures exercise the pool spend, position spend and identity burn together.
fn closure_fixture(empty: Bool, locked: Bool, time: Int) -> Transaction {
  let base = stake_topup_fixture()
  expect [pool_in, position_in] = base.inputs
  let pool = PoolDatum { ..read_pool(pool_in.output), is_locked: locked }
  let previous = read_position(position_in.output)
  let position = if empty {
    PositionDatum { ..previous, staked_amount: 0, pending_rewards: 0 }
  } else {
    previous
  }
  let checkpoint = rewards.checkpoint_pool(pool, time)
  let reward = rewards.calculate_earned(
    position,
    checkpoint.reward_per_token_stored,
  )
  let pool_data: Data = Pool(pool)
  let position_data: Data = Position(position)
  let after_data: Data = Pool(
    PoolDatum {
      ..checkpoint,
      total_staked: pool.total_staked - position.staked_amount,
      accrued_liability_bound: checkpoint.accrued_liability_bound - reward,
    },
  )
  let action: Data = if empty {
    CloseEmptyPosition { position_id: position.position_name }
  } else {
    Exit { position_id: position.position_name }
  }
  Transaction {
    ..base,
    inputs: [
      Input {
        ..pool_in,
        output: Output { ..pool_in.output, datum: InlineDatum(pool_data) },
      },
      Input {
        ..position_in,
        output: Output {
          ..position_in.output,
          datum: InlineDatum(position_data),
        },
      },
    ],
    outputs: [
      Output {
        ..pool_in.output,
        datum: InlineDatum(after_data),
        value: pool_in.output.value
          |> assets.add(fixture_asset_policy, #"41", -position.staked_amount)
          |> assets.add(fixture_asset_policy, #"42", -reward),
      },
      Output {
        address: position.payout_address,
        value: assets.from_asset(
          fixture_asset_policy,
          #"41",
          position.staked_amount,
        )
          |> assets.add(fixture_asset_policy, #"42", reward)
          |> assets.add(#"", #"", assets.lovelace_of(position_in.output.value)),
        datum: transaction.NoDatum,
        reference_script: None,
      },
    ],
    mint: assets.from_asset(fixture_policy, position.position_name, -1),
    validity_range: notify_range(time * 1000, ( time + 30 ) * 1000),
    redeemers: [
      Pair(Spend(pool_in.output_reference), action),
      Pair(Spend(position_in.output_reference), action),
    ],
  }
}

fn closure_validate(config: PoolConfig, tx: Transaction) -> Bool {
  expect [pool_in, position_in] = tx.inputs
  let position = read_position(position_in.output)
  let action = spending_action(tx, pool_in.output_reference)
  and {
    single_staking.spend(
      config.bootstrap_ref,
      config.manager,
      config.rewards_distributor,
      config.staking_asset,
      config.reward_asset,
      config.initially_locked,
      config.vault_supported,
      config.factory_policy,
      Some(Pool(read_pool(pool_in.output))),
      action,
      pool_in.output_reference,
      tx,
    ),
    single_staking.spend(
      config.bootstrap_ref,
      config.manager,
      config.rewards_distributor,
      config.staking_asset,
      config.reward_asset,
      config.initially_locked,
      config.vault_supported,
      config.factory_policy,
      Some(Position(position)),
      action,
      position_in.output_reference,
      tx,
    ),
    single_staking.mint(
      config.bootstrap_ref,
      config.manager,
      config.rewards_distributor,
      config.staking_asset,
      config.reward_asset,
      config.initially_locked,
      config.vault_supported,
      config.factory_policy,
      ClosePosition { position_id: position.position_name },
      fixture_policy,
      tx,
    ),
  }
}

test exit_closes_position_paying_principal_rewards_and_ada() {
  closure_validate(fixture_config(), closure_fixture(False, False, 160))
}

test exit_locked_before_finish_rejected() fail {
  closure_validate(fixture_config(), closure_fixture(False, True, 160))
}

test exit_locked_at_finish_rejected() fail {
  closure_validate(fixture_config(), closure_fixture(False, True, 600))
}

test exit_locked_after_finish_succeeds() {
  closure_validate(fixture_config(), closure_fixture(False, True, 601))
}

test close_empty_succeeds_while_locked() {
  closure_validate(fixture_config(), closure_fixture(True, True, 160))
}

test closure_requires_owner() fail {
  let tx = closure_fixture(False, False, 160)
  closure_validate(
    fixture_config(),
    Transaction { ..tx, extra_signatories: [] },
  )
}

test closure_requires_burning_position_nft() fail {
  let tx = closure_fixture(False, False, 160)
  closure_validate(fixture_config(), Transaction { ..tx, mint: assets.zero })
}

test closure_rejects_extra_protocol_mint() fail {
  let tx = closure_fixture(False, False, 160)
  closure_validate(
    fixture_config(),
    Transaction { ..tx, mint: tx.mint |> assets.add(fixture_policy, #"aa", 1) },
  )
}

test closure_rejects_mismatched_position_action() fail {
  let tx = closure_fixture(False, False, 160)
  let wrong: Data = Claim { position_id: position_token_name(fixture_ref(2)) }
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      redeemers: [
        list.expect_head(tx.redeemers),
        Pair(Spend(fixture_ref(4)), wrong),
      ],
    },
  )
}

test closure_cannot_redirect_payout() {
  let tx = closure_fixture(False, False, 160)
  expect [pool_out, payout] = tx.outputs
  !closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output {
          ..payout,
          address: address.from_verification_key(
            #"99999999999999999999999999999999999999999999999999999999",
          ),
        },
      ],
    },
  )
}

test closure_must_return_position_ada() {
  let tx = closure_fixture(False, False, 160)
  expect [pool_out, payout] = tx.outputs
  !closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output { ..payout, value: payout.value |> assets.add(#"", #"", -1) },
      ],
    },
  )
}

test exit_must_pay_all_principal() {
  let tx = closure_fixture(False, False, 160)
  expect [pool_out, payout] = tx.outputs
  !closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output {
          ..payout,
          value: payout.value |> assets.add(fixture_asset_policy, #"41", -1),
        },
      ],
    },
  )
}

test exit_must_pay_all_rewards() {
  let tx = closure_fixture(False, False, 160)
  expect [pool_out, payout] = tx.outputs
  !closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output {
          ..payout,
          value: payout.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
      ],
    },
  )
}

test exit_cannot_extract_extra_pool_rewards() {
  let tx = closure_fixture(False, False, 160)
  expect [pool_out, payout] = tx.outputs
  !closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..pool_out,
          value: pool_out.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
        payout,
      ],
    },
  )
}

test closure_cannot_extract_pool_ada() {
  let tx = closure_fixture(True, False, 160)
  expect [pool_out, payout] = tx.outputs
  !closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        Output { ..pool_out, value: pool_out.value |> assets.add(#"", #"", -1) },
        payout,
      ],
    },
  )
}

test close_empty_rejects_remaining_stake() fail {
  let tx = closure_fixture(True, False, 160)
  expect [pool_in, position_in] = tx.inputs
  let data: Data = Position(
    PositionDatum { ..read_position(position_in.output), staked_amount: 1 },
  )
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      inputs: [
        pool_in,
        Input {
          ..position_in,
          output: Output { ..position_in.output, datum: InlineDatum(data) },
        },
      ],
    },
  )
}

test close_empty_rejects_pending_rewards() fail {
  let tx = closure_fixture(True, False, 160)
  expect [pool_in, position_in] = tx.inputs
  let data: Data = Position(
    PositionDatum { ..read_position(position_in.output), pending_rewards: 1 },
  )
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      inputs: [
        pool_in,
        Input {
          ..position_in,
          output: Output { ..position_in.output, datum: InlineDatum(data) },
        },
      ],
    },
  )
}

test closure_rejects_remaining_position_marker() fail {
  let tx = closure_fixture(True, False, 160)
  expect [pool_out, payout] = tx.outputs
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output {
          ..payout,
          value: payout.value
            |> assets.add(
                fixture_policy,
                position_token_name(fixture_ref(2)),
                1,
              ),
        },
      ],
    },
  )
}

fn same_asset_exit(extra: Int) -> Bool {
  let tx = closure_fixture(False, False, 160)
  expect [pool_in, position_in] = tx.inputs
  expect [pool_out, payout] = tx.outputs
  let config = fixture_config()
  let updated = Transaction {
    ..tx,
    inputs: [
      Input {
        ..pool_in,
        output: Output {
          ..pool_in.output,
          value: pool_in.output.value
            |> assets.add(fixture_asset_policy, #"42", -6000)
            |> assets.add(fixture_asset_policy, #"41", 6000),
        },
      },
      position_in,
    ],
    outputs: [
      Output {
        ..pool_out,
        value: pool_out.value
          |> assets.add(fixture_asset_policy, #"42", -5400)
          |> assets.add(fixture_asset_policy, #"41", 5400 - extra),
      },
      Output {
        ..payout,
        value: payout.value
          |> assets.add(fixture_asset_policy, #"42", -600)
          |> assets.add(fixture_asset_policy, #"41", 600 + extra),
      },
    ],
  }
  closure_validate(
    PoolConfig { ..config, reward_asset: config.staking_asset },
    updated,
  )
}

test exit_same_asset_combines_principal_and_rewards() {
  same_asset_exit(0)
}

test exit_same_asset_cannot_extract_surplus() {
  !same_asset_exit(1)
}

test closure_rejects_tampered_checkpoint() fail {
  let tx = closure_fixture(False, False, 160)
  expect [pool_out, payout] = tx.outputs
  let data: Data = Pool(
    PoolDatum { ..read_pool(pool_out), accrued_liability_bound: 1 },
  )
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      outputs: [Output { ..pool_out, datum: InlineDatum(data) }, payout],
    },
  )
}

test closure_rejects_stale_position_checkpoint() fail {
  let tx = closure_fixture(False, False, 160)
  expect [pool_in, position_in] = tx.inputs
  let data: Data = Position(
    PositionDatum {
      ..read_position(position_in.output),
      reward_per_token_paid: 1,
    },
  )
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      inputs: [
        pool_in,
        Input {
          ..position_in,
          output: Output { ..position_in.output, datum: InlineDatum(data) },
        },
      ],
    },
  )
}

test closure_rejects_wide_validity_interval() fail {
  let tx = closure_fixture(False, False, 160)
  closure_validate(
    fixture_config(),
    Transaction { ..tx, validity_range: notify_range(160_000, 221_000) },
  )
}

test exit_without_principal_can_claim_and_close_while_locked() {
  let tx = closure_fixture(True, True, 160)
  expect [pool_in, position_in] = tx.inputs
  expect [pool_out, payout] = tx.outputs
  let position = read_position(position_in.output)
  let data: Data = Position(PositionDatum { ..position, pending_rewards: 600 })
  let after_data: Data = Pool(
    PoolDatum { ..read_pool(pool_out), accrued_liability_bound: 0 },
  )
  let action: Data = Exit { position_id: position.position_name }
  closure_validate(
    fixture_config(),
    Transaction {
      ..tx,
      inputs: [
        pool_in,
        Input {
          ..position_in,
          output: Output { ..position_in.output, datum: InlineDatum(data) },
        },
      ],
      outputs: [
        Output {
          ..pool_out,
          datum: InlineDatum(after_data),
          value: pool_out.value |> assets.add(fixture_asset_policy, #"42", -600),
        },
        Output {
          ..payout,
          value: payout.value |> assets.add(fixture_asset_policy, #"42", 600),
        },
      ],
      redeemers: [
        Pair(Spend(fixture_ref(3)), action),
        Pair(Spend(fixture_ref(4)), action),
      ],
    },
  )
}

fn fund_fixture() -> Transaction {
  let base = notify_fixture(True)
  let input = list.expect_head(base.inputs)
  let action: Data = FundRewards { amount: 3000 }
  Transaction {
    ..base,
    outputs: [
      Output {
        ..input.output,
        value: input.output.value
          |> assets.add(fixture_asset_policy, #"42", 3000),
      },
    ],
    redeemers: [Pair(Spend(input.output_reference), action)],
  }
}

fn fund_validate(config: PoolConfig, amount: Int, tx: Transaction) -> Bool {
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    FundRewards { amount },
    input.output_reference,
    tx,
  )
}

test fund_adds_reserves_without_changing_any_pool_fields() {
  fund_validate(notify_config(), 3000, fund_fixture())
}

test fund_requires_distributor_not_manager() fail {
  let tx = fund_fixture()
  fund_validate(
    notify_config(),
    3000,
    Transaction { ..tx, extra_signatories: [fixture_manager] },
  )
}

test fund_requires_positive_amount() fail {
  fund_validate(notify_config(), 0, fund_fixture())
}

test fund_rejects_negative_amount() fail {
  fund_validate(notify_config(), -1, fund_fixture())
}

test fund_rejects_underfunding() {
  let tx = fund_fixture()
  let out = list.expect_head(tx.outputs)
  !fund_validate(
    notify_config(),
    3000,
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..out,
          value: out.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
      ],
    },
  )
}

test fund_rejects_wrong_declared_amount() {
  !fund_validate(notify_config(), 2999, fund_fixture())
}

test fund_cannot_change_emission_schedule() {
  let tx = fund_fixture()
  let out = list.expect_head(tx.outputs)
  let data: Data = Pool(PoolDatum { ..read_pool(out), reward_rate: 999 })
  !fund_validate(
    notify_config(),
    3000,
    Transaction { ..tx, outputs: [Output { ..out, datum: InlineDatum(data) }] },
  )
}

test fund_cannot_checkpoint_or_change_lock() {
  let tx = fund_fixture()
  let out = list.expect_head(tx.outputs)
  let data: Data = Pool(
    PoolDatum { ..read_pool(out), last_update_seconds: 160, is_locked: False },
  )
  !fund_validate(
    notify_config(),
    3000,
    Transaction { ..tx, outputs: [Output { ..out, datum: InlineDatum(data) }] },
  )
}

test fund_cannot_take_principal() {
  let tx = fund_fixture()
  let out = list.expect_head(tx.outputs)
  !fund_validate(
    notify_config(),
    3000,
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..out,
          value: out.value |> assets.add(fixture_asset_policy, #"41", -1),
        },
      ],
    },
  )
}

test fund_cannot_take_pool_ada() {
  let tx = fund_fixture()
  let out = list.expect_head(tx.outputs)
  !fund_validate(
    notify_config(),
    3000,
    Transaction {
      ..tx,
      outputs: [Output { ..out, value: out.value |> assets.add(#"", #"", -1) }],
    },
  )
}

test fund_cannot_mint_protocol_tokens() fail {
  let tx = fund_fixture()
  fund_validate(
    notify_config(),
    3000,
    Transaction { ..tx, mint: assets.from_asset(fixture_policy, #"aa", 1) },
  )
}

test fund_same_asset_keeps_principal_and_adds_only_declared_reserves() {
  let tx = fund_fixture()
  let input = list.expect_head(tx.inputs)
  let out = list.expect_head(tx.outputs)
  let config = notify_config()
  fund_validate(
    PoolConfig { ..config, reward_asset: config.staking_asset },
    3000,
    Transaction {
      ..tx,
      inputs: [
        Input {
          ..input,
          output: Output {
            ..input.output,
            value: input.output.value
              |> assets.add(fixture_asset_policy, #"42", -6000)
              |> assets.add(fixture_asset_policy, #"41", 6000),
          },
        },
      ],
      outputs: [
        Output {
          ..out,
          value: out.value
            |> assets.add(fixture_asset_policy, #"42", -9000)
            |> assets.add(fixture_asset_policy, #"41", 9000),
        },
      ],
    },
  )
}

fn pause_fixture(paused: Bool) -> Transaction {
  let base = fund_fixture()
  let input = list.expect_head(base.inputs)
  let before = PoolDatum { ..read_pool(input.output), is_paused: paused }
  let before_data: Data = Pool(before)
  let after_data: Data = Pool(PoolDatum { ..before, is_paused: !paused })
  let action: Data = TogglePause
  Transaction {
    ..base,
    inputs: [
      Input {
        ..input,
        output: Output { ..input.output, datum: InlineDatum(before_data) },
      },
    ],
    outputs: [Output { ..input.output, datum: InlineDatum(after_data) }],
    extra_signatories: [fixture_manager],
    redeemers: [Pair(Spend(input.output_reference), action)],
  }
}

fn pause_validate(tx: Transaction) -> Bool {
  let config = notify_config()
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    TogglePause,
    input.output_reference,
    tx,
  )
}

test manager_can_pause() {
  pause_validate(pause_fixture(False))
}

test manager_can_unpause() {
  pause_validate(pause_fixture(True))
}

test pause_distributor_is_not_manager() fail {
  let tx = pause_fixture(False)
  pause_validate(Transaction { ..tx, extra_signatories: [fixture_distributor] })
}

test pause_requires_signature() fail {
  pause_validate(Transaction { ..pause_fixture(False), extra_signatories: [] })
}

test pause_must_flip_flag() {
  let tx = pause_fixture(False)
  let input = list.expect_head(tx.inputs)
  !pause_validate(Transaction { ..tx, outputs: [input.output] })
}

test pause_cannot_change_lock_or_schedule() {
  let tx = pause_fixture(False)
  let output = list.expect_head(tx.outputs)
  let data: Data = Pool(
    PoolDatum { ..read_pool(output), is_locked: False, reward_rate: 999 },
  )
  !pause_validate(
    Transaction {
      ..tx,
      outputs: [Output { ..output, datum: InlineDatum(data) }],
    },
  )
}

test pause_cannot_remove_assets_or_ada() {
  let tx = pause_fixture(False)
  let output = list.expect_head(tx.outputs)
  !pause_validate(
    Transaction {
      ..tx,
      outputs: [
        Output { ..output, value: output.value |> assets.add(#"", #"", -1) },
      ],
    },
  )
}

test pause_cannot_add_assets() {
  let tx = pause_fixture(False)
  let output = list.expect_head(tx.outputs)
  !pause_validate(
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..output,
          value: output.value |> assets.add(fixture_asset_policy, #"42", 1),
        },
      ],
    },
  )
}

test pause_cannot_mint_identity() fail {
  let tx = pause_fixture(False)
  pause_validate(
    Transaction { ..tx, mint: assets.from_asset(fixture_policy, #"aa", 1) },
  )
}

fn lock_fixture(locked: Bool) -> Transaction {
  let tx = pause_fixture(False)
  let input = list.expect_head(tx.inputs)
  let before = PoolDatum { ..read_pool(input.output), is_locked: locked }
  let before_data: Data = Pool(before)
  let after_data: Data = Pool(PoolDatum { ..before, is_locked: !locked })
  let action: Data = ToggleWithdrawLock
  Transaction {
    ..tx,
    inputs: [
      Input {
        ..input,
        output: Output { ..input.output, datum: InlineDatum(before_data) },
      },
    ],
    outputs: [Output { ..input.output, datum: InlineDatum(after_data) }],
    redeemers: [Pair(Spend(input.output_reference), action)],
  }
}

fn lock_validate(tx: Transaction) -> Bool {
  let config = notify_config()
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    ToggleWithdrawLock,
    input.output_reference,
    tx,
  )
}

test manager_can_enable_withdraw_lock() {
  lock_validate(lock_fixture(False))
}

test manager_can_disable_withdraw_lock() {
  lock_validate(lock_fixture(True))
}

test lock_requires_manager_not_distributor() fail {
  lock_validate(
    Transaction {
      ..lock_fixture(False),
      extra_signatories: [fixture_distributor],
    },
  )
}

test lock_requires_signature() fail {
  lock_validate(Transaction { ..lock_fixture(False), extra_signatories: [] })
}

test lock_must_flip_flag() {
  let tx = lock_fixture(False)
  !lock_validate(
    Transaction { ..tx, outputs: [list.expect_head(tx.inputs).output] },
  )
}

test lock_cannot_change_pause_or_deadline() {
  let tx = lock_fixture(False)
  let out = list.expect_head(tx.outputs)
  let data: Data = Pool(
    PoolDatum { ..read_pool(out), is_paused: True, period_finish_seconds: 999 },
  )
  !lock_validate(
    Transaction { ..tx, outputs: [Output { ..out, datum: InlineDatum(data) }] },
  )
}

test lock_cannot_change_pool_value() {
  let tx = lock_fixture(False)
  let out = list.expect_head(tx.outputs)
  !lock_validate(
    Transaction {
      ..tx,
      outputs: [Output { ..out, value: out.value |> assets.add(#"", #"", -1) }],
    },
  )
}

test lock_cannot_mint_protocol_tokens() fail {
  lock_validate(
    Transaction {
      ..lock_fixture(False),
      mint: assets.from_asset(fixture_policy, #"aa", 1),
    },
  )
}

fn recovery_fixture(asset: AssetClass, amount: Int, time: Int) -> Transaction {
  let base = fund_fixture()
  let original = list.expect_head(base.inputs)
  let input = Input {
    ..original,
    output: Output {
      ..original.output,
      value: original.output.value
        |> assets.add(fixture_asset_policy, #"42", 1000),
    },
  }
  let checkpoint = rewards.checkpoint_pool(read_pool(input.output), time)
  let data: Data = Pool(checkpoint)
  let action: Data = RecoverSurplus { asset, amount }
  Transaction {
    ..base,
    inputs: [input],
    outputs: [
      Output {
        ..input.output,
        datum: InlineDatum(data),
        value: input.output.value
          |> assets.add(asset.policy_id, asset.token_name, -amount),
      },
      Output {
        address: address.from_verification_key(fixture_manager),
        value: assets.from_asset(asset.policy_id, asset.token_name, amount)
          |> assets.add(#"", #"", 2_000_000),
        datum: transaction.NoDatum,
        reference_script: None,
      },
    ],
    extra_signatories: [fixture_manager],
    validity_range: notify_range(time * 1000, ( time + 30 ) * 1000),
    redeemers: [Pair(Spend(input.output_reference), action)],
  }
}

fn recovery_validate(asset: AssetClass, amount: Int, tx: Transaction) -> Bool {
  let config = notify_config()
  let input = list.expect_head(tx.inputs)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    RecoverSurplus { asset, amount },
    input.output_reference,
    tx,
  )
}

test recover_reward_surplus_preserves_active_obligations() {
  let asset = fixture_config().reward_asset
  recovery_validate(asset, 1, recovery_fixture(asset, 1, 160))
}

test recover_cannot_take_scheduled_rewards() {
  let asset = fixture_config().reward_asset
  !recovery_validate(asset, 1001, recovery_fixture(asset, 1001, 160))
}

test recover_after_expiry_still_protects_accrued_rewards() {
  let asset = fixture_config().reward_asset
  !recovery_validate(asset, 1001, recovery_fixture(asset, 1001, 800))
}

test recover_cannot_take_staked_principal() {
  let asset = fixture_config().staking_asset
  !recovery_validate(asset, 1, recovery_fixture(asset, 1, 160))
}

test recover_requires_manager() fail {
  let asset = fixture_config().reward_asset
  let tx = recovery_fixture(asset, 1, 160)
  recovery_validate(
    asset,
    1,
    Transaction { ..tx, extra_signatories: [fixture_distributor] },
  )
}

test recover_rejects_zero() fail {
  let asset = fixture_config().reward_asset
  recovery_validate(asset, 0, recovery_fixture(asset, 0, 160))
}

test recover_rejects_ada() fail {
  let asset = AssetClass { policy_id: #"", token_name: #"" }
  recovery_validate(asset, 1, recovery_fixture(asset, 1, 160))
}

test recover_rejects_protocol_identity() fail {
  let asset = AssetClass {
    policy_id: fixture_policy,
    token_name: pool_token_name,
  }
  recovery_validate(asset, 1, recovery_fixture(asset, 1, 160))
}

test recover_requires_manager_payout() {
  let asset = fixture_config().reward_asset
  let tx = recovery_fixture(asset, 1, 160)
  expect [pool_out, payout] = tx.outputs
  !recovery_validate(
    asset,
    1,
    Transaction {
      ..tx,
      outputs: [
        pool_out,
        Output {
          ..payout,
          address: address.from_verification_key(fixture_distributor),
        },
      ],
    },
  )
}

fn recovery_same_asset(amount: Int) -> Bool {
  let config = notify_config()
  let tx = recovery_fixture(config.reward_asset, amount, 160)
  let input = list.expect_head(tx.inputs)
  expect [output, payout] = tx.outputs
  let updated = Transaction {
    ..tx,
    inputs: [
      Input {
        ..input,
        output: Output {
          ..input.output,
          value: input.output.value
            |> assets.add(fixture_asset_policy, #"42", -7000)
            |> assets.add(fixture_asset_policy, #"41", 7000),
        },
      },
    ],
    outputs: [
      Output {
        ..output,
        value: output.value
          |> assets.add(fixture_asset_policy, #"42", -(7000 - amount))
          |> assets.add(fixture_asset_policy, #"41", 7000 - amount),
      },
      Output {
        ..payout,
        value: payout.value
          |> assets.add(fixture_asset_policy, #"42", -amount)
          |> assets.add(fixture_asset_policy, #"41", amount),
      },
    ],
  }
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.staking_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    RecoverSurplus { asset: config.staking_asset, amount },
    input.output_reference,
    updated,
  )
}

test recover_same_asset_preserves_principal_plus_rewards() {
  recovery_same_asset(1000)
}

test recover_same_asset_cannot_take_principal_or_rewards() {
  !recovery_same_asset(1001)
}

test recover_unrelated_native_token_leaves_obligations_intact() {
  let asset = AssetClass { policy_id: fixture_asset_policy, token_name: #"43" }
  let tx = recovery_fixture(asset, 100, 160)
  let input = list.expect_head(tx.inputs)
  expect [output, payout] = tx.outputs
  recovery_validate(
    asset,
    100,
    Transaction {
      ..tx,
      inputs: [
        Input {
          ..input,
          output: Output {
            ..input.output,
            value: input.output.value
              |> assets.add(asset.policy_id, asset.token_name, 100),
          },
        },
      ],
      outputs: [
        Output {
          ..output,
          value: output.value
            |> assets.add(asset.policy_id, asset.token_name, 100),
        },
        payout,
      ],
    },
  )
}

test recover_cannot_skip_liability_checkpoint() {
  let asset = fixture_config().reward_asset
  let tx = recovery_fixture(asset, 1, 160)
  let input = list.expect_head(tx.inputs)
  expect [output, payout] = tx.outputs
  !recovery_validate(
    asset,
    1,
    Transaction {
      ..tx,
      outputs: [Output { ..output, datum: input.output.datum }, payout],
    },
  )
}

test recover_cannot_take_pool_ada_as_side_effect() {
  let asset = fixture_config().reward_asset
  let tx = recovery_fixture(asset, 1, 160)
  expect [output, payout] = tx.outputs
  !recovery_validate(
    asset,
    1,
    Transaction {
      ..tx,
      outputs: [
        Output { ..output, value: output.value |> assets.add(#"", #"", -1) },
        payout,
      ],
    },
  )
}

// Vault eligibility is immutable script configuration; ownership support follows separately.
test vault_supported_initialization_unlocked_succeeds() {
  let config = PoolConfig {
    ..fixture_config(),
    initially_locked: False,
    vault_supported: True,
    factory_policy: Some(fixture_factory_policy),
  }
  let tx = Transaction {
    ..fixture_init(),
    outputs: [
      fixture_output(
        pool_token_name,
        Pool(PoolDatum { ..fixture_pool(), is_locked: False }),
      ),
    ],
  }
  validate_initialize_pool(config, fixture_policy, tx)
}

test vault_supported_initialization_locked_fails() fail {
  let config = PoolConfig {
    ..fixture_config(),
    vault_supported: True,
    factory_policy: Some(fixture_factory_policy),
  }
  validate_initialize_pool(config, fixture_policy, fixture_init())
}

test vault_supported_manager_cannot_enable_lock() fail {
  let config = PoolConfig {
    ..fixture_config(),
    initially_locked: False,
    vault_supported: True,
    factory_policy: Some(fixture_factory_policy),
  }
  validate_toggle_lock(
    config,
    PoolDatum { ..fixture_pool(), is_locked: False },
    fixture_ref(3),
    lock_fixture(False),
  )
}

test open_position_rejects_unsupported_schema_version() fail {
  fixture_validate(
    OpenPosition {
      schema_version: 1,
      creation_ref: fixture_ref(2),
      owner: WalletOwner(fixture_manager),
    },
    fixture_open(),
  )
}

test position_datum_rejects_unsupported_schema_version() fail {
  expect [_, output] = fixture_open().outputs
  let position = read_position(output)
  read_position(
    fixture_output(
      position.position_name,
      Position(PositionDatum { ..position, schema_version: 1 }),
    ),
  ) == position
}

test vault_owner_cannot_use_wallet_signature() fail {
  expect [_, output] = fixture_open().outputs
  let position = read_position(output)
  wallet_position_authorized(
    fixture_open(),
    PositionDatum {
      ..position,
      owner: VaultOwner {
        controller: fixture_manager,
        state_policy: fixture_asset_policy,
        state_name: #"5354415445",
      },
    },
  )
}

test vault_open_without_factory_and_state_evidence_rejected() fail {
  let tx = fixture_open()
  expect [pool, output] = tx.outputs
  let position = read_position(output)
  let owner = VaultOwner {
    controller: fixture_manager,
    state_policy: fixture_asset_policy,
    state_name: #"5354415445",
  }
  validate_open_position(
    PoolConfig {
      ..fixture_config(),
      initially_locked: False,
      vault_supported: True,
      factory_policy: Some(fixture_factory_policy),
    },
    fixture_policy,
    fixture_ref(2),
    owner,
    Transaction {
      ..tx,
      outputs: [
        pool,
        fixture_output(
          position.position_name,
          Position(PositionDatum { ..position, owner }),
        ),
      ],
    },
  )
}

test vault_pool_initialization_requires_explicit_factory_policy() fail {
  let config = PoolConfig {
    ..fixture_config(),
    initially_locked: False,
    vault_supported: True,
    factory_policy: None,
  }
  validate_initialize_pool(config, fixture_policy, fixture_init())
}

test wallet_pool_initialization_rejects_factory_policy() fail {
  let config = PoolConfig {
    ..fixture_config(),
    factory_policy: Some(fixture_factory_policy),
  }
  validate_initialize_pool(config, fixture_policy, fixture_init())
}

test vault_pool_initialization_rejects_malformed_factory_policy() fail {
  let config = PoolConfig {
    ..fixture_config(),
    initially_locked: False,
    vault_supported: True,
    factory_policy: Some(#"00"),
  }
  validate_initialize_pool(config, fixture_policy, fixture_init())
}

// Component transactions exercise the complete staking handlers. Certificate
// issuance and the independent controller program are covered in their own repo.
fn combined_fixture(amount: Int) -> Transaction {
  let tx = withdraw_fixture(amount, False, 160)
  expect [pool_input, position_input] = tx.inputs
  expect [pool_output, position_output, payout] = tx.outputs
  let before = read_pool(pool_input.output)
  let checkpoint = rewards.checkpoint_pool(before, 160)
  let previous = read_position(position_input.output)
  let accrued = rewards.checkpoint_position(
    previous,
    checkpoint.reward_per_token_stored,
  )
  let reward = accrued.pending_rewards
  let after: Data = Pool(
    PoolDatum {
      ..checkpoint,
      total_staked: before.total_staked - amount,
      accrued_liability_bound: checkpoint.accrued_liability_bound - reward,
    },
  )
  let next: Data = Position(
    PositionDatum {
      ..accrued,
      staked_amount: previous.staked_amount - amount,
      pending_rewards: 0,
    },
  )
  let action: Data = WithdrawAndClaim {
    amount,
    position_id: previous.position_name,
  }
  Transaction {
    ..tx,
    outputs: [
      Output {
        ..pool_output,
        datum: InlineDatum(after),
        value: pool_output.value
          |> assets.add(fixture_asset_policy, #"42", -reward),
      },
      Output { ..position_output, datum: InlineDatum(next) },
      Output {
        ..payout,
        value: payout.value |> assets.add(fixture_asset_policy, #"42", reward),
      },
    ],
    redeemers: [
      Pair(Spend(pool_input.output_reference), action),
      Pair(Spend(position_input.output_reference), action),
    ],
  }
}

fn combined_validate(tx: Transaction) -> Bool {
  expect [pool_input, position_input, ..] = tx.inputs
  let position = read_position(position_input.output)
  let action = spending_action(tx, pool_input.output_reference)
  let config = fixture_config()
  and {
    single_staking.spend(
      config.bootstrap_ref,
      config.manager,
      config.rewards_distributor,
      config.staking_asset,
      config.reward_asset,
      config.initially_locked,
      config.vault_supported,
      config.factory_policy,
      Some(Pool(read_pool(pool_input.output))),
      action,
      pool_input.output_reference,
      tx,
    ),
    single_staking.spend(
      config.bootstrap_ref,
      config.manager,
      config.rewards_distributor,
      config.staking_asset,
      config.reward_asset,
      config.initially_locked,
      config.vault_supported,
      config.factory_policy,
      Some(Position(position)),
      action,
      position_input.output_reference,
      tx,
    ),
  }
}

test wallet_combined_exit_settles_rewards_and_preserves_position() {
  combined_validate(combined_fixture(40))
}

test wallet_combined_exit_cannot_redirect_rewards() {
  let tx = combined_fixture(40)
  expect [pool, position, payout] = tx.outputs
  !combined_validate(
    Transaction {
      ..tx,
      outputs: [
        pool,
        position,
        Output {
          ..payout,
          value: payout.value |> assets.add(fixture_asset_policy, #"42", -1),
        },
      ],
    },
  )
}

fn vault_owner() -> PositionOwner {
  VaultOwner {
    controller: fixture_manager,
    state_policy: fixture_manager,
    state_name: #"5354415445",
  }
}

fn vault_config() -> PoolConfig {
  PoolConfig {
    ..fixture_config(),
    initially_locked: False,
    vault_supported: True,
    factory_policy: Some(fixture_factory_policy),
  }
}

fn test_vault_state() -> Output {
  Output {
    address: address.from_script(fixture_manager),
    value: assets.from_lovelace(3_000_000)
      |> assets.add(fixture_manager, #"5354415445", 1),
    datum: InlineDatum(builtin.i_data(0)),
    reference_script: None,
  }
}

fn test_base_action(entering: Bool, amount: Int, state_output: Int) -> Data {
  let destination = builtin.constr_data(
    0,
    [
      builtin.constr_data(
        0,
        [
          builtin.constr_data(0, [builtin.b_data(fixture_manager)]),
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
        if entering {
          0
        } else {
          2
        },
        [
          destination,
          builtin.i_data(amount),
          builtin.i_data(1),
          builtin.i_data(state_output),
          builtin.i_data(state_output + 1),
        ],
      ),
    ],
  )
}

fn test_admission_refs_for(
  controller: PolicyId,
  seed_ref: OutputReference,
) -> List<Input> {
  let principal: Data = admission.NativeAsset {
    policy_id: fixture_asset_policy,
    asset_name: #"41",
  }
  let terms = builtin.constr_data(
    0,
    [
      builtin.i_data(0),
      builtin.b_data(#""),
      principal,
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
  let seed: Data = fixture_ref(10)
  let base = builtin.constr_data(
    3,
    [
      builtin.b_data(#"43545653"),
      builtin.i_data(2),
      builtin.b_data(controller),
      seed,
      builtin.b_data(blake2b_256(builtin.serialise_data(terms))),
      terms,
      builtin.i_data(3_000_000),
    ],
  )
  let config: Data = admission.Extension {
    base,
    binding: admission.Binding {
      pool_policy: fixture_policy,
      position_seed: seed_ref,
      reward_asset: admission.NativeAsset {
        policy_id: fixture_asset_policy,
        asset_name: #"42",
      },
    },
  }
  let certificate = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(controller),
      builtin.b_data(controller),
      builtin.b_data(#"5354415445"),
      builtin.b_data(#"43545653312d4d495845442d464143544f52592d31"),
      builtin.b_data(blake2b_256(#"696e7374616e6365")),
      builtin.b_data(blake2b_256(builtin.serialise_data(config))),
    ],
  )
  [
    Input {
      output_reference: fixture_ref(11),
      output: Output {
        address: address.from_script(fixture_factory_policy),
        value: assets.from_asset(fixture_factory_policy, controller, 1),
        datum: InlineDatum(certificate),
        reference_script: None,
      },
    },
    Input {
      output_reference: fixture_ref(12),
      output: Output {
        address: address.from_script(fixture_factory_policy),
        value: assets.from_asset(controller, #"4944", 1),
        datum: InlineDatum(config),
        reference_script: None,
      },
    },
  ]
}

fn vault_transaction(
  tx: Transaction,
  entering: Bool,
  amount: Int,
  creation: Option<OutputReference>,
) -> Transaction {
  let update = fn(output: Output) {
    if assets.quantity_of(output.value, fixture_policy, pool_token_name) != 0 {
      let pool = read_pool(output)
      let raw: Data = Pool(PoolDatum { ..pool, is_locked: False })
      Output { ..output, datum: InlineDatum(raw) }
    } else if assets.quantity_of(
      output.value,
      fixture_policy,
      position_token_name(fixture_ref(2)),
    ) != 0 {
      let position = read_position(output)
      let raw: Data = Position(
        PositionDatum {
          ..position,
          owner: vault_owner(),
          payout_address: address.from_script(fixture_manager),
        },
      )
      Output { ..output, datum: InlineDatum(raw) }
    } else {
      output
    }
  }
  let state_output = list.length(tx.outputs)
  let approved: Data = authorization.AuthorizeStaking {
    version: 1,
    pool_id: fixture_policy,
    position_name: position_token_name(fixture_ref(2)),
    operation: if entering {
      authorization.Stake
    } else {
      authorization.WithdrawAndClaim
    },
    amount,
    creation_ref: creation,
    state_output,
    base: test_base_action(entering, amount, state_output),
    max_reward_input: 0,
    min_reward_output: 0,
  }
  Transaction {
    ..tx,
    inputs: list.map(
      tx.inputs,
      fn(i) { Input { ..i, output: update(i.output) } },
    )
      |> list.push(
          Input { output_reference: fixture_ref(5), output: test_vault_state() },
        ),
    outputs: list.concat(list.map(tx.outputs, update), [test_vault_state()]),
    extra_signatories: [],
    reference_inputs: if creation == None {
      []
    } else {
      test_admission_refs_for(fixture_manager, fixture_ref(2))
    },
    redeemers: [Pair(Spend(fixture_ref(5)), approved), ..tx.redeemers],
  }
}

fn vault_stake_validate(
  tx: Transaction,
  amount: Int,
  creation: Option<OutputReference>,
) -> Bool {
  let config = vault_config()
  let input = pool_input(tx, fixture_policy)
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Pool(read_pool(input.output))),
    Stake {
      amount,
      position_id: position_token_name(fixture_ref(2)),
      creation_ref: creation,
    },
    input.output_reference,
    tx,
  )
}

test admitted_vault_creation_validates_mint_and_pool_spend() {
  let tx = vault_transaction(
    stake_new_fixture(),
    True,
    100,
    Some(fixture_ref(2)),
  )
  and {
    validate_open_position(
      vault_config(),
      fixture_policy,
      fixture_ref(2),
      vault_owner(),
      tx,
    ),
    vault_stake_validate(tx, 100, Some(fixture_ref(2))),
  }
}

test vault_creation_without_factory_reference_rejected() fail {
  let tx = vault_transaction(
    stake_new_fixture(),
    True,
    100,
    Some(fixture_ref(2)),
  )
  validate_open_position(
    vault_config(),
    fixture_policy,
    fixture_ref(2),
    vault_owner(),
    Transaction { ..tx, reference_inputs: [] },
  )
}

test vault_topup_does_not_require_registration_again() {
  vault_stake_validate(
    vault_transaction(stake_topup_fixture(), True, 50, None),
    50,
    None,
  )
}

test vault_combined_exit_requires_no_registration_and_retains_storage() {
  let tx = vault_transaction(combined_fixture(40), False, 40, None)
  let input = pool_input(tx, fixture_policy)
  validate_withdraw_and_claim(
    vault_config(),
    read_pool(input.output),
    40,
    position_token_name(fixture_ref(2)),
    input.output_reference,
    tx,
  )
}

test vault_standalone_claim_cannot_bypass_controller_accounting() fail {
  let tx = vault_transaction(combined_fixture(40), False, 40, None)
  let input = pool_input(tx, fixture_policy)
  validate_claim(
    vault_config(),
    read_pool(input.output),
    position_token_name(fixture_ref(2)),
    input.output_reference,
    tx,
  )
}

test vault_wallet_signature_is_not_controller_permission() fail {
  let tx = vault_transaction(stake_topup_fixture(), True, 50, None)
  vault_stake_validate(
    Transaction {
      ..tx,
      redeemers: stake_topup_fixture().redeemers,
      extra_signatories: [fixture_manager],
    },
    50,
    None,
  )
}

fn with_other_stake(tx: Transaction, amount: Int) -> Transaction {
  let add = fn(out: Output) {
    if assets.quantity_of(out.value, fixture_policy, pool_token_name) == 1 {
      let before = read_pool(out)
      let raw: Data = Pool(
        PoolDatum { ..before, total_staked: before.total_staked + amount },
      )
      Output {
        ..out,
        datum: InlineDatum(raw),
        value: out.value |> assets.add(fixture_asset_policy, #"41", amount),
      }
    } else {
      out
    }
  }
  Transaction {
    ..tx,
    inputs: list.map(tx.inputs, fn(i) { Input { ..i, output: add(i.output) } }),
    outputs: list.map(tx.outputs, add),
  }
}

test vault_first_entry_preserves_existing_wallet_principal() {
  let tx = with_other_stake(
    vault_transaction(stake_new_fixture(), True, 100, Some(fixture_ref(2))),
    100,
  )
  and {
    validate_open_position(
      vault_config(),
      fixture_policy,
      fixture_ref(2),
      vault_owner(),
      tx,
    ),
    vault_stake_validate(tx, 100, Some(fixture_ref(2))),
    read_pool(pool_output(tx, fixture_policy)).total_staked == 200,
  }
}

test distinct_second_vault_can_enter_after_wallet_and_first_vault() {
  let controller = #"66666666666666666666666666666666666666666666666666666666"
  let seed = fixture_ref(6)
  let old_name = position_token_name(fixture_ref(2))
  let name = position_token_name(seed)
  let owner = VaultOwner {
    controller,
    state_policy: controller,
    state_name: #"5354415445",
  }
  let tx = with_other_stake(
    vault_transaction(stake_new_fixture(), True, 100, Some(fixture_ref(2))),
    200,
  )
  let rebind = fn(out: Output) {
    if assets.quantity_of(out.value, fixture_policy, old_name) == 1 {
      let position = read_position(out)
      let raw: Data = Position(
        PositionDatum {
          ..position,
          owner,
          position_name: name,
          payout_address: address.from_script(controller),
        },
      )
      Output {
        ..out,
        datum: InlineDatum(raw),
        value: out.value
          |> assets.add(fixture_policy, old_name, -1)
          |> assets.add(fixture_policy, name, 1),
      }
    } else if assets.quantity_of(out.value, fixture_manager, #"5354415445") == 1 {
      Output {
        ..out,
        address: address.from_script(controller),
        value: out.value
          |> assets.add(fixture_manager, #"5354415445", -1)
          |> assets.add(controller, #"5354415445", 1),
      }
    } else {
      out
    }
  }
  let action = Stake {
    amount: 100,
    position_id: name,
    creation_ref: Some(seed),
  }
  let raw_action: Data = action
  let approved: Data = authorization.AuthorizeStaking {
    version: 1,
    pool_id: fixture_policy,
    position_name: name,
    operation: authorization.Stake,
    amount: 100,
    creation_ref: Some(seed),
    state_output: 2,
    base: test_base_action(True, 100, 2),
    max_reward_input: 0,
    min_reward_output: 0,
  }
  let next = Transaction {
    ..tx,
    inputs: list.map(
      tx.inputs,
      fn(i) {
        Input {
          ..i,
          output_reference: if i.output_reference == fixture_ref(2) {
            seed
          } else {
            i.output_reference
          },
          output: rebind(i.output),
        }
      },
    ),
    outputs: list.map(tx.outputs, rebind),
    reference_inputs: test_admission_refs_for(controller, seed),
    mint: assets.from_asset(fixture_policy, name, 1),
    redeemers: [
      Pair(Spend(fixture_ref(5)), approved),
      Pair(Spend(fixture_ref(1)), raw_action),
    ],
  }
  let config = vault_config()
  let input = pool_input(next, fixture_policy)
  and {
    validate_open_position(config, fixture_policy, seed, owner, next),
    single_staking.spend(
      config.bootstrap_ref,
      config.manager,
      config.rewards_distributor,
      config.staking_asset,
      config.reward_asset,
      config.initially_locked,
      config.vault_supported,
      config.factory_policy,
      Some(Pool(read_pool(input.output))),
      action,
      input.output_reference,
      next,
    ),
    read_pool(pool_output(next, fixture_policy)).total_staked == 300,
  }
}

test vault_topup_rejects_cross_position_action_reuse() fail {
  let tx = vault_transaction(stake_topup_fixture(), True, 50, None)
  vault_stake_validate(tx, 50, Some(fixture_ref(6)))
}

test vault_combined_exit_cannot_extract_unearned_pool_rewards() {
  let tx = vault_transaction(combined_fixture(40), False, 40, None)
  let input = pool_input(tx, fixture_policy)
  let out = pool_output(tx, fixture_policy)
  !validate_withdraw_and_claim(
    vault_config(),
    read_pool(input.output),
    40,
    position_token_name(fixture_ref(2)),
    input.output_reference,
    Transaction {
      ..tx,
      outputs: list.map(
        tx.outputs,
        fn(o) {
          if o == out {
            Output {
              ..o,
              value: o.value |> assets.add(fixture_asset_policy, #"42", -1),
            }
          } else {
            o
          }
        },
      ),
    },
  )
}

test admitted_vault_creation_executes_identity_mint_handler() {
  let tx = vault_transaction(
    stake_new_fixture(),
    True,
    100,
    Some(fixture_ref(2)),
  )
  let config = vault_config()
  single_staking.mint(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    OpenPosition {
      schema_version: 2,
      creation_ref: fixture_ref(2),
      owner: vault_owner(),
    },
    fixture_policy,
    tx,
  )
}

test vault_combined_exit_executes_position_handler() {
  let tx = vault_transaction(combined_fixture(40), False, 40, None)
  expect [position_input] = list.filter(
    tx.inputs,
    fn(i) {
      assets.quantity_of(
        i.output.value,
        fixture_policy,
        position_token_name(fixture_ref(2)),
      ) == 1
    },
  )
  let config = vault_config()
  single_staking.spend(
    config.bootstrap_ref,
    config.manager,
    config.rewards_distributor,
    config.staking_asset,
    config.reward_asset,
    config.initially_locked,
    config.vault_supported,
    config.factory_policy,
    Some(Position(read_position(position_input.output))),
    WithdrawAndClaim {
      amount: 40,
      position_id: position_token_name(fixture_ref(2)),
    },
    position_input.output_reference,
    tx,
  )
}

test vault_standalone_withdraw_cannot_bypass_combined_exit() fail {
  let tx = vault_transaction(withdraw_fixture(40, False, 160), False, 40, None)
  let pool = pool_input(tx, fixture_policy)
  validate_withdraw(
    vault_config(),
    read_pool(pool.output),
    40,
    position_token_name(fixture_ref(2)),
    pool.output_reference,
    tx,
  )
}
