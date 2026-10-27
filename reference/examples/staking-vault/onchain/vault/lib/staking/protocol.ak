// Current staking wire adapter: version 2 positions and atomic WithdrawAndClaim.
use aiken/builtin
use aiken/crypto.{blake2b_256}
use aiken/interval.{Finite}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use staking/types.{PoolDatum, PositionDatum, PositionOwner}

pub type AssetClass {
  policy_id: PolicyId,
  token_name: AssetName,
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

pub fn position_token_name(creation_ref: OutputReference) -> AssetName {
  let data: Data = creation_ref
  blake2b_256(builtin.serialise_data(data))
}

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

pub const pool_token_name = #"504f4f4c"
