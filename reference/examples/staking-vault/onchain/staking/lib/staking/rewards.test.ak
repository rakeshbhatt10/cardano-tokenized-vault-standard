use cardano/address
use staking/rewards
use staking/types.{
  PoolDatum, PositionDatum, WalletOwner, position_schema_version,
}

fn pool() -> PoolDatum {
  PoolDatum {
    total_staked: 1000,
    reward_duration_seconds: 600,
    period_finish_seconds: 600,
    reward_rate: 10,
    last_update_seconds: 0,
    reward_per_token_stored: 0,
    accrued_liability_bound: 0,
    is_paused: False,
    is_locked: False,
  }
}

fn alice() -> PositionDatum {
  PositionDatum {
    schema_version: position_schema_version,
    pool_id: #"",
    position_name: #"",
    owner: WalletOwner(#""),
    payout_address: address.from_verification_key(#""),
    staked_amount: 100,
    reward_per_token_paid: 0,
    pending_rewards: 0,
  }
}

test alice_earns_60_then_10_after_claim() {
  let first_pool = rewards.checkpoint_pool(pool(), 60)
  let first_position = rewards.checkpoint_position(
    alice(),
    first_pool.reward_per_token_stored,
  )
  let after_claim = PositionDatum { ..first_position, pending_rewards: 0 }
  let paid_pool = PoolDatum {
    ..first_pool,
    accrued_liability_bound: first_pool.accrued_liability_bound - 60,
  }
  and {
    first_position.pending_rewards == 60,
    rewards.calculate_earned(
      after_claim,
      rewards.reward_per_token(paid_pool, 70),
    ) == 10,
    first_pool.accrued_liability_bound == 600,
  }
}

test expiry_caps_emissions() {
  let next = rewards.checkpoint_pool(
    PoolDatum { ..pool(), period_finish_seconds: 60 },
    90,
  )
  and {
    next.last_update_seconds == 60,
    next.accrued_liability_bound == 600,
  }
}

test zero_stake_preserves_accumulator_and_adds_no_liability() {
  let empty = PoolDatum {
    ..pool(),
    total_staked: 0,
    reward_per_token_stored: 42,
  }
  let next = rewards.checkpoint_pool(empty, 60)
  and {
    next.reward_per_token_stored == 42,
    next.accrued_liability_bound == 0,
    next.last_update_seconds == 60,
  }
}

test rounding_and_pending_rewards() {
  let next = rewards.checkpoint_pool(
    PoolDatum { ..pool(), total_staked: 3, reward_rate: 1 },
    1,
  )
  rewards.calculate_earned(
    PositionDatum { ..alice(), staked_amount: 1, pending_rewards: 7 },
    next.reward_per_token_stored,
  ) == 7
}

test backwards_time_rejected() fail {
  rewards.checkpoint_pool(PoolDatum { ..pool(), last_update_seconds: 60 }, 59) == pool()
}

test negative_stake_rejected() fail {
  rewards.checkpoint_pool(PoolDatum { ..pool(), total_staked: -1 }, 60) == pool()
}

test backwards_accumulator_rejected() fail {
  rewards.calculate_earned(
    PositionDatum { ..alice(), reward_per_token_paid: 1 },
    0,
  ) == 0
}
