import {
	decodeAuthorization,
	record,
	stakingAction,
} from "../../protocol/shared-v1/authorization.ts";
import { openPosition } from "../staking/position.ts";
import { Data } from "@lucid-evolution/lucid";
import {
	validateFactoryGenesis,
	type FactoryGenesisIntent,
} from "./factory-genesis.ts";
import {
	validatePlan,
	type IndexedOutput,
	type PlanInput,
	type TransactionPlan,
} from "@ctvs/planning";
import { encodeData, hex, refId, type PlutusData } from "@ctvs/protocol";

export type ComposedPlan = Omit<
	TransactionPlan,
	"schema" | "inputs" | "outputs"
> & {
	schema: "STAKING-CTVS1-PLAN-1";
	stateAuthorization?: "shared-v1";
	factoryGenesis?: FactoryGenesisIntent;
	inputs: (Omit<PlanInput, "role"> & {
		role:
			| PlanInput["role"]
			| "staking_pool"
			| "staking_position"
			| "position_seed";
	})[];
	outputs: (Omit<IndexedOutput, "role"> & {
		role:
			| IndexedOutput["role"]
			| "staking_pool"
			| "staking_position"
			| "registration";
	})[];
	staking?: {
		poolPolicy: string;
		positionName: string;
		mode?: "reward_notification";
	};
};

export function unwrapStateRedeemer(
	raw: PlutusData,
	profile: "shared-v1" = "shared-v1",
): PlutusData {
	if (profile !== "shared-v1") throw Error("Unsupported controller authorization profile");
	return decodeAuthorization(raw).base;
}

/** Extend the pinned intent format without weakening its checks for ordinary plans. */
export function validateComposedPlan<T extends ComposedPlan>(plan: T): T {
	if (plan.schema !== "STAKING-CTVS1-PLAN-1")
		throw new Error("Expected local staking intent schema");
	if (
		plan.stateAuthorization !== undefined &&
		plan.stateAuthorization !== "shared-v1" &&
		plan.stateAuthorization !== "shared-v1"
	)
		throw new Error("Unknown controller authorization profile");
	if (plan.stateAuthorization === "shared-v1" && !plan.staking) {
		for (const input of plan.inputs.filter((i) => i.role === "state"))
			if (
				!input.redeemer ||
				decodeAuthorization(input.redeemer).kind !== "maintenance"
			)
				throw new Error(
					"Staking authorization requires composed staking effects",
				);
	}
	if (plan.staking && plan.stateAuthorization !== "shared-v1") throw Error("Current staking authorization required");
	const foreign = plan.inputs.filter(
		(i) =>
			i.role === "staking_pool" ||
			i.role === "staking_position" ||
			i.role === "position_seed",
	);
	const poolMint = plan.mint.filter(
		(m) => m.policy !== plan.implementation.policy,
	);
	if (plan.factoryGenesis) validateFactoryGenesis(plan);
	if (
		!plan.staking &&
		(foreign.length || (poolMint.length && !plan.factoryGenesis))
	)
		throw new Error("Foreign staking execution without a binding");
	if (plan.staking) {
		const { poolPolicy, positionName } = plan.staking;
		if (
			plan.stateAuthorization === "shared-v1" &&
			plan.staking.mode !== "reward_notification"
		) {
			const input = plan.inputs.find((i) => i.role === "state");
			if (!input?.redeemer)
				throw new Error("Shared State authorization is missing");
			const a = decodeAuthorization(input.redeemer);
			if (
				a.kind !== "staking" ||
				a.poolId !== poolPolicy ||
				a.positionName !== positionName
			)
				throw new Error("Shared staking identity mismatch");
			const expected = hex(encodeData(stakingAction(a)));
			const action = record(record(a.base).fields[2]!);
			const operations = ["deposit", "mint", "withdraw", "redeem"];
			if (operations[Number(action.constr)] !== plan.operation)
				throw new Error(
					"Shared inner action does not match the planned operation",
				);
			const state = plan.outputs.filter((o) => o.role === "state");
			if (state.length !== 1 || state[0]!.index !== a.stateOutput)
				throw new Error("Shared State continuation index mismatch");
			for (const [role, policy, name] of [
				["state", plan.implementation.policy, "5354415445"],
				["staking_pool", poolPolicy, "504f4f4c"],
				["staking_position", poolPolicy, positionName],
			] as const) {
				const unit = policy + "." + name;
				const outputs = plan.outputs.filter(
					(o) => (o.value[unit] ?? 0n) !== 0n,
				);
				if (
					outputs.length !== 1 ||
					outputs[0]!.role !== role ||
					outputs[0]!.value[unit] !== 1n ||
					outputs[0]!.address.payment.type !== "script" ||
					outputs[0]!.address.payment.hash !== policy ||
					outputs[0]!.address.stake !== null ||
					outputs[0]!.datumMode !== "inline" ||
					outputs[0]!.referenceScript !== null
				)
					throw new Error("Shared identity continuation mismatch: " + role);
			}
			for (const i of plan.inputs.filter(
				(i) => i.role === "staking_pool" || i.role === "staking_position",
			))
				if (!i.redeemer || hex(encodeData(i.redeemer)) !== expected)
					throw new Error("Shared staking action mismatch");
			const seed = plan.inputs.find((i) => i.role === "position_seed");
			if (
				a.creationRef
					? !seed || refId(seed.ref) !== refId(a.creationRef)
					: !!seed
			)
				throw new Error("Shared creation mode mismatch");
			if (a.creationRef) {
				if (
					poolMint.length !== 1 ||
					hex(encodeData(poolMint[0]!.redeemer)) !==
						Data.to(
							openPosition(a.creationRef, plan.implementation.policy),
						)
				)
					throw new Error("Shared OpenPosition authorization mismatch");
			}
		}

		if (
			!/^[0-9a-f]{56}$/.test(poolPolicy) ||
			!/^[0-9a-f]{64}$/.test(positionName) ||
			poolPolicy === plan.implementation.policy
		) {
			throw new Error("Invalid staking intent identity");
		}
		if (
			plan.inputs.filter((i) => i.role === "state").length !==
				(plan.staking.mode === "reward_notification" ? 0 : 1) ||
			plan.inputs.filter((i) => i.role === "staking_pool").length !== 1 ||
			plan.inputs.filter((i) => i.role === "staking_position").length > 1 ||
			plan.inputs.filter((i) => i.role === "position_seed").length > 1
		) {
			throw new Error("Invalid composed input roles");
		}
		if (
			plan.staking.mode === "reward_notification" &&
			(plan.inputs.length !== 1 || plan.mint.length !== 0)
		)
			throw new Error("Reward notification cannot move vault State or mint");
		if (plan.staking.mode !== "reward_notification") {
			const seeds = plan.inputs.filter(
				(i) => i.role === "position_seed",
			).length;
			const positions = plan.inputs.filter(
				(i) => i.role === "staking_position",
			).length;
			if (seeds + positions !== 1 || poolMint.length !== seeds)
				throw new Error(
					"Exactly one existing position or one-shot position creation is required",
				);
		}
		for (const i of foreign) {
			if (
				i.role === "position_seed" ? i.redeemer !== null : i.redeemer === null
			)
				throw new Error("Invalid staking role redeemer");
			if (i.redeemer !== null) encodeData(i.redeemer);
		}
		if (
			poolMint.length > 1 ||
			poolMint.some(
				(m) =>
					m.policy !== poolPolicy ||
					Object.keys(m.assets).length !== 1 ||
					m.assets[positionName] !== 1n,
			)
		) {
			throw new Error("Unapproved staking identity mint");
		}
	}
	const consumed = new Set(plan.inputs.map((i) => refId(i.ref)));
	if (
		consumed.size !== plan.inputs.length ||
		new Set(plan.referenceInputs.map(refId)).size !==
			plan.referenceInputs.length ||
		plan.referenceInputs.some((r) => consumed.has(refId(r)))
	)
		throw new Error("Duplicate or overlapping composed input");
	// The reference validator still validates base redeemers, output shapes, mint,
	// signers, bounds and the unsigned boundary. Extension redeemers stay in the
	// real plan, where the complete-effects verifier matches their exact CBOR.
	validatePlan<TransactionPlan>({
		...plan,
		schema: "CTVS-REFERENCE-PLAN-1",
		inputs: plan.inputs
			.filter(
				(i) =>
					i.role !== "staking_pool" &&
					i.role !== "staking_position" &&
					i.role !== "position_seed",
			)
			.map((i) => ({
				...i,
				role: i.role as PlanInput["role"],
				redeemer:
					i.role === "state" && i.redeemer !== null
						? unwrapStateRedeemer(i.redeemer, plan.stateAuthorization)
						: i.redeemer,
			})),
		outputs: plan.outputs.map((o) => ({
			...o,
			role:
				o.role === "staking_pool" ||
				o.role === "staking_position" ||
				o.role === "registration"
					? "state"
					: o.role,
		})),
		mint: plan.mint.filter((m) => m.policy === plan.implementation.policy),
	});
	return plan;
}
