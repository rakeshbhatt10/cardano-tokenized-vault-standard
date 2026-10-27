use cardano/transaction.{OutputReference}
use ctvs/wire.{Asset}

// Pool ID is approved once at genesis, after deriving the vault then the pool.
// This removes hash recursion without granting a post-genesis replacement power.
pub type PoolBinding {
  pool_policy: ByteArray,
  position_seed: OutputReference,
  reward_asset: Asset,
}

pub type StakingConfig {
  base: Data,
  binding: PoolBinding,
}

pub type StakingSpend {
  base: Data,
  max_reward_input: Int,
  min_reward_output: Int,
}
