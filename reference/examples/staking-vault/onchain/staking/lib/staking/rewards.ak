use staking/types.{PoolDatum, PositionDatum}

// Base-unit integers and seconds. Integer division rounds down for nonnegative inputs.
pub const precision: Int = 1_000_000_000_000_000_000

fn validate_pool(pool: PoolDatum) -> Bool {
  and {
    pool.total_staked >= 0,
    pool.reward_duration_seconds >= 0,
    pool.period_finish_seconds >= 0,
    pool.reward_rate >= 0,
    pool.last_update_seconds >= 0,
    pool.last_update_seconds <= pool.period_finish_seconds,
    pool.reward_per_token_stored >= 0,
    pool.accrued_liability_bound >= 0,
  }
}

pub fn last_time_reward_applicable(pool: PoolDatum, time_seconds: Int) -> Int {
  expect validate_pool(pool)
  expect time_seconds >= 0
  let applicable = if time_seconds < pool.period_finish_seconds {
    time_seconds
  } else {
    pool.period_finish_seconds
  }
  expect applicable >= pool.last_update_seconds
  applicable
}

pub fn checkpoint_pool(pool: PoolDatum, time_seconds: Int) -> PoolDatum {
  let applicable = last_time_reward_applicable(pool, time_seconds)
  let emission = if pool.total_staked == 0 {
    0
  } else {
    ( applicable - pool.last_update_seconds ) * pool.reward_rate
  }
  let increment = if pool.total_staked == 0 {
    0
  } else {
    emission * precision / pool.total_staked
  }
  PoolDatum {
    ..pool,
    last_update_seconds: applicable,
    reward_per_token_stored: pool.reward_per_token_stored + increment,
    accrued_liability_bound: pool.accrued_liability_bound + emission,
  }
}

pub fn reward_per_token(pool: PoolDatum, time_seconds: Int) -> Int {
  checkpoint_pool(pool, time_seconds).reward_per_token_stored
}

pub fn calculate_earned(position: PositionDatum, reward_per_token: Int) -> Int {
  expect and {
      position.staked_amount >= 0,
      position.reward_per_token_paid >= 0,
      position.pending_rewards >= 0,
      reward_per_token >= position.reward_per_token_paid,
    }
  position.pending_rewards + position.staked_amount * (
    reward_per_token - position.reward_per_token_paid
  ) / precision
}

// This accrues rewards but does not reset them or authorize a payout.
pub fn checkpoint_position(
  position: PositionDatum,
  reward_per_token: Int,
) -> PositionDatum {
  PositionDatum {
    ..position,
    pending_rewards: calculate_earned(position, reward_per_token),
    reward_per_token_paid: reward_per_token,
  }
}
