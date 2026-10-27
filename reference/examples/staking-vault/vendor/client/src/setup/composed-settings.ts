import { z } from "zod";
import { decodeData } from "@ctvs/protocol";
import { existingPoolProgramSchema } from "./existing-pool-program.ts";

const hash = (size: number) =>
	z.string().regex(new RegExp(`^[0-9a-f]{${size * 2}}$`));
const decimal = z
	.string()
	.regex(/^(0|[1-9][0-9]{0,18})$/)
	.refine((v) => BigInt(v) <= (1n << 63n) - 1n);
const q = decimal.transform((v) => BigInt(v));
const positive = q.refine((v) => v > 0n);
const ref = z
	.object({ txId: hash(32), index: q.refine((v) => v <= 65535n) })
	.strict();
const name = z.string().regex(/^(?:[0-9a-f]{2}){0,32}$/);
const asset = z.object({ policy: hash(28), name }).strict();
const poolAsset = z.object({ policyId: hash(28), tokenNameHex: name }).strict();
const credential = z
	.object({ type: z.enum(["key", "script"]), hash: hash(28) })
	.strict();
const destination = z
	.object({
		address: z
			.object({ payment: credential, stake: credential.nullable() })
			.strict(),
		datumCbor: z
			.string()
			.regex(/^(?:[0-9a-f]{2})+$/)
			.nullable(),
	})
	.strict();
const terms = z
	.object({
		profile: z.literal("0").transform(() => 0n),
		networkDomain: hash(32),
		underlying: asset,
		virtualShares: positive,
		maxBacking: positive.nullable(),
		entryBps: q,
		exitBps: q,
		feeDestination: destination,
		pauseKey: hash(28).nullable(),
		settlers: z.array(hash(28)).nullable(),
		executionModes: z.literal("3").transform(() => 3n),
		maxBatch: positive,
		descriptorHash: hash(32).nullable(),
	})
	.strict()
	.transform((v) => ({
		...v,
		feeDestination: {
			address: v.feeDestination.address,
			datum:
				v.feeDestination.datumCbor === null
					? null
					: decodeData(v.feeDestination.datumCbor),
		},
	}));
const network = z.enum(["Preview", "Preprod"]);
const schema = z
	.object({
		vault: z
			.object({
				network,
				terms,
				seed: ref,
				configReserve: positive,
				stateReserve: positive,
				chainPoint: z.object({ slot: q, blockHash: hash(32) }).strict(),
			})
			.strict(),
		pool: z
			.object({
				network,
				sourcePool: z.literal("test2-test1"),
				bootstrapRef: z
					.object({
						txHash: hash(32),
						outputIndex: decimal.refine((v) => BigInt(v) <= 65535n),
					})
					.strict(),
				manager: hash(28),
				rewardsDistributor: hash(28),
				fundingAddress: z.string(),
				stakingAsset: poolAsset,
				rewardAsset: poolAsset,
				poolReserveLovelace: decimal.refine((v) => BigInt(v) > 0n),
				referenceReserveLovelace: decimal.refine((v) => BigInt(v) > 0n),
			})
			.strict(),
		positionSeed: ref,
	})
	.strict();

const stakingSchema = schema.extend({
	pool: schema.shape.pool.extend({
		initiallyLocked: z.literal(false),
		vaultSupported: z.literal(true),
	}),
});
const factorySchema = stakingSchema.extend({
	vault: schema.shape.vault,
	pool: stakingSchema.shape.pool.extend({
		sourcePool: z.enum(["test2-test1", "custom"]),
		factoryPolicy: hash(28),
		stakingBuild: z.literal("mixed-owner-v1"),
		deployedProgram: existingPoolProgramSchema.optional(),
	}),
});
/** Automatic factory preparation has no privileged per-instance approval field. */
export function readFactorySettings(
	input: unknown,
): Parameters<
	typeof import("../factory/deployment.ts").prepareFactoryDeployment
>[0] {
	return factorySchema.parse(input);
}
