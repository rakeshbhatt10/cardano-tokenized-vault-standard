import {
	constr,
	bytes,
	outRefData,
	encodeData,
	hex,
	refId,
	type OutRef,
	type PlutusData,
} from "@ctvs/protocol";
import { decodeRegistration } from "../../protocol/shared-v1/registration.ts";
import type { ComposedPlan } from "./model.ts";

export interface FactoryGenesisIntent {
	policy: string;
	instance: PlutusData;
	prefix0: OutRef;
	prefix1: OutRef;
}

/** Narrow genesis-only extension; ordinary plans still reject every foreign mint. */
export function validateFactoryGenesis(plan: ComposedPlan) {
	const f = plan.factoryGenesis!;
	const policy = plan.implementation.policy;
	if (
		plan.operation !== "genesis" ||
		plan.staking ||
		plan.stateAuthorization ||
		plan.implementation.family !== "ctvs1" ||
		!/^[0-9a-f]{56}$/.test(f.policy) ||
		f.policy === policy ||
		plan.inputs.length !== 1 ||
		plan.inputs[0]!.role !== "genesis_seed" ||
		plan.outputs.length !== 3 ||
		plan.mint.length !== 2 ||
		plan.requiredSigners.length ||
		plan.validity !== null ||
		refId(f.prefix0) === refId(f.prefix1) ||
		![f.prefix0, f.prefix1].every((r) =>
			plan.referenceInputs.some((i) => refId(i) === refId(r)),
		)
	)
		throw Error("Invalid factory genesis intent");
	const own = plan.mint.filter((m) => m.policy === policy);
	const foreign = plan.mint.filter((m) => m.policy !== policy);
	const expected = constr(0, [
		f.instance,
		outRefData(f.prefix0),
		outRefData(f.prefix1),
		0n,
		1n,
		2n,
	]);
	if (
		own.length !== 1 ||
		foreign.length !== 1 ||
		foreign[0]!.policy !== f.policy ||
		Object.keys(foreign[0]!.assets).length !== 1 ||
		foreign[0]!.assets[policy] !== 1n ||
		hex(encodeData(foreign[0]!.redeemer)) !== hex(encodeData(expected)) ||
		Object.keys(own[0]!.assets).sort().join() !==
			["4944", "5354415445"].sort().join() ||
		own[0]!.assets["4944"] !== 1n ||
		own[0]!.assets["5354415445"] !== 1n ||
		hex(encodeData(own[0]!.redeemer)) !==
			hex(encodeData(constr(3, [bytes("43545653"), 2n, constr(0, [0n, 1n])])))
	)
		throw Error("Invalid factory genesis mint");
	const [config, state, certificate] = plan.outputs;
	if (
		config!.index !== 0n ||
		config!.role !== "config" ||
		state!.index !== 1n ||
		state!.role !== "state" ||
		certificate!.index !== 2n ||
		certificate!.role !== "registration" ||
		!certificate!.datum ||
		certificate!.address.payment.type !== "script" ||
		certificate!.address.payment.hash !== plan.implementation.configLock ||
		certificate!.address.stake !== null ||
		certificate!.datumMode !== "inline" ||
		certificate!.referenceScript !== null ||
		Object.keys(certificate!.value).sort().join() !==
			["ada", f.policy + "." + policy].sort().join() ||
		certificate!.value[f.policy + "." + policy] !== 1n ||
		(certificate!.value.ada ?? 0n) <= 0n
	)
		throw Error("Invalid factory registration output");
	const registration = decodeRegistration(certificate!.datum);
	if (
		registration.controller !== policy ||
		registration.statePolicy !== policy ||
		registration.stateName !== "5354415445"
	)
		throw Error("Registration controller/State identity mismatch");
}
