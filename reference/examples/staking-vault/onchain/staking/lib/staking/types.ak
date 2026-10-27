use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}

pub type PoolDatum {
  total_staked: Int,
  reward_duration_seconds: Int,
  period_finish_seconds: Int,
  reward_rate: Int,
  last_update_seconds: Int,
  reward_per_token_stored: Int,
  accrued_liability_bound: Int,
  is_paused: Bool,
  is_locked: Bool,
}

pub type PositionOwner {
  WalletOwner(VerificationKeyHash)
  VaultOwner {
    controller: ScriptHash,
    state_policy: PolicyId,
    state_name: AssetName,
  }
}

pub const position_schema_version = 2

pub type PositionDatum {
  schema_version: Int,
  pool_id: PolicyId,
  position_name: AssetName,
  owner: PositionOwner,
  payout_address: Address,
  staked_amount: Int,
  reward_per_token_paid: Int,
  pending_rewards: Int,
}
