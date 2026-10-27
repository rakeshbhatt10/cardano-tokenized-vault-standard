/** Off-chain estimates only. The Aiken validator must independently verify them. */
export const PRECISION = 10n ** 18n;

export type PoolRewards = {
	totalStaked: bigint;
	periodFinishSeconds: bigint;
	rewardRate: bigint;
	lastUpdateSeconds: bigint;
	rewardPerTokenStored: bigint;
	accruedLiabilityBound: bigint;
};
export type PositionRewards = {
	stakedAmount: bigint;
	rewardPerTokenPaid: bigint;
	pendingRewards: bigint;
};
function nonnegative(values: bigint[]) {
	if (values.some((value) => value < 0n)) {
		throw new Error("Reward inputs must be nonnegative.");
	}
}
export function lastTimeRewardApplicable(
	pool: PoolRewards,
	timeSeconds: bigint,
): bigint {
	nonnegative([...Object.values(pool), timeSeconds]);
	const applicable =
		timeSeconds < pool.periodFinishSeconds
			? timeSeconds
			: pool.periodFinishSeconds;
	if (applicable < pool.lastUpdateSeconds) {
		throw new Error("Reward time cannot move backwards.");
	}
	return applicable;
}
export function checkpointPool(
	pool: PoolRewards,
	timeSeconds: bigint,
): PoolRewards {
	const applicable = lastTimeRewardApplicable(pool, timeSeconds);
	const emission =
		pool.totalStaked === 0n
			? 0n
			: (applicable - pool.lastUpdateSeconds) * pool.rewardRate;
	return {
		...pool,
		lastUpdateSeconds: applicable,
		rewardPerTokenStored:
			pool.rewardPerTokenStored +
			(pool.totalStaked === 0n
				? 0n
				: (emission * PRECISION) / pool.totalStaked),
		accruedLiabilityBound: pool.accruedLiabilityBound + emission,
	};
}
export function rewardPerToken(pool: PoolRewards, timeSeconds: bigint): bigint {
	return checkpointPool(pool, timeSeconds).rewardPerTokenStored;
}
export function earned(
	position: PositionRewards,
	rewardPerToken: bigint,
): bigint {
	nonnegative([...Object.values(position), rewardPerToken]);
	if (rewardPerToken < position.rewardPerTokenPaid) {
		throw new Error("Reward accumulator cannot move backwards.");
	}
	return (
		position.pendingRewards +
		(position.stakedAmount * (rewardPerToken - position.rewardPerTokenPaid)) /
			PRECISION
	);
}
export function checkpointPosition(
	position: PositionRewards,
	rewardPerToken: bigint,
): PositionRewards {
	return {
		...position,
		pendingRewards: earned(position, rewardPerToken),
		rewardPerTokenPaid: rewardPerToken,
	};
}
export function previewClaim(
	pool: PoolRewards,
	position: PositionRewards,
	timeSeconds: bigint,
) {
	const nextPool = checkpointPool(pool, timeSeconds);
	const nextPosition = checkpointPosition(
		position,
		nextPool.rewardPerTokenStored,
	);
	return {
		pool: nextPool,
		position: nextPosition,
		rewardAmount: nextPosition.pendingRewards,
	};
}

/** Same schedule arithmetic as validate_notify_rewards; reserve checks are separate. */
export function previewNotifyRewards(
	pool: PoolRewards,
	reward: bigint,
	durationSeconds: bigint,
	timeSeconds: bigint,
) {
	if (reward <= 0n || durationSeconds <= 0n) {
		throw new Error("Reward and duration must be positive.");
	}
	const checkpoint = checkpointPool(pool, timeSeconds);
	const remaining =
		pool.periodFinishSeconds > timeSeconds
			? pool.periodFinishSeconds - timeSeconds
			: 0n;
	const periodFinishSeconds = timeSeconds + durationSeconds;
	if (periodFinishSeconds < pool.periodFinishSeconds) {
		throw new Error("Cannot shorten the existing reward period.");
	}
	return {
		...checkpoint,
		rewardRate: (reward + remaining * pool.rewardRate) / durationSeconds,
		rewardDurationSeconds: durationSeconds,
		periodFinishSeconds,
		lastUpdateSeconds: timeSeconds,
	};
}
