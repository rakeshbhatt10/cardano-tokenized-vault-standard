import { applyParamsToScript } from "../../../support/application.ts";
import {  type Script } from "@lucid-evolution/lucid";
import type { FactoryBlueprint } from "./build.ts";
import { blake, rawScript } from "./hashing.ts";

export type FactoryProofMode = "staking-vault";
export interface FactoryPolicyParameters {
	prefixHash: string;
	suffix: string;
	configLock: string;
}
const INSTANCE_HASH_BYTES = 32;
const implementations = {
	"staking-vault": {
		controller: "factory_vault.vault",
		factory: "authenticated_factory.authenticated_factory",
	},
} as const;

function template(
	blueprint: FactoryBlueprint,
	title: string,
	parameterCount: number,
) {
	const matches = blueprint.validators.filter(
		(validator) => validator.title === title,
	);
	if (
		matches.length !== 1 ||
		(matches[0]!.parameters?.length ?? 0) !== parameterCount
	)
		throw Error("Wrong factory template");
	return matches[0]!.compiledCode;
}
/** Select the intended implementation explicitly and require identical compiled
 * programs across its handlers. No prototype implementation is selectable. */
export function selectFactoryTemplates(
	blueprint: FactoryBlueprint,
	mode: FactoryProofMode,
) {
	if (mode !== "staking-vault") throw Error("Unsupported factory implementation");
	const names = implementations[mode];
	const controllerTemplate = template(blueprint, names.controller + ".mint", 1);
	if (template(blueprint, names.controller + ".else", 1) !== controllerTemplate)
		throw Error("Controller handler mismatch");
	const factoryTemplate = template(blueprint, names.factory + ".mint", 3);
	if (template(blueprint, names.factory + ".else", 3) !== factoryTemplate)
		throw Error("Factory handler mismatch");
	return {
		controllerTemplate,
		factoryTemplate,
		lockTemplate: template(blueprint, "config_lock.config_lock.else", 0),
	};
}

/** Locate the instance parameter by applying two distinct 32-byte test hashes.
 * Exactly those 32 adjacent bytes must change; all surrounding bytes are fixed. */
export function deriveControllerLayout(controllerTemplate: string) {
	const first = rawScript(
		applyParamsToScript(controllerTemplate, ["11".repeat(INSTANCE_HASH_BYTES)]),
	);
	const second = rawScript(
		applyParamsToScript(controllerTemplate, ["22".repeat(INSTANCE_HASH_BYTES)]),
	);
	const changedOffsets = Array.from(first).flatMap((byte, index) =>
		byte !== second[index] ? [index] : [],
	);
	if (
		first.length !== second.length ||
		changedOffsets.length !== INSTANCE_HASH_BYTES ||
		changedOffsets[INSTANCE_HASH_BYTES - 1]! - changedOffsets[0] !==
			INSTANCE_HASH_BYTES - 1
	)
		throw Error("Unsupported fixed-width application layout");
	const offset = changedOffsets[0]!,
		prefix = first.subarray(0, offset),
		suffix = first.subarray(offset + INSTANCE_HASH_BYTES);
	if (
		!first
			.subarray(offset, offset + INSTANCE_HASH_BYTES)
			.equals(Buffer.alloc(INSTANCE_HASH_BYTES, 0x11))
	)
		throw Error("Parameter layout mismatch");
	return { prefix, suffix };
}

/** These are the three immutable authenticated_factory parameters, in named form. */
export function prepareFactoryPolicyParameters(
	layout: ReturnType<typeof deriveControllerLayout>,
	configLock: string,
): FactoryPolicyParameters {
	return {
		prefixHash: blake(layout.prefix),
		suffix: layout.suffix.toString("hex"),
		configLock,
	};
}
/** Parameter order must match the Aiken validator declaration exactly. */
export function applyFactoryPolicyParameters(
	factoryTemplate: string,
	parameters: FactoryPolicyParameters,
): Script {
	return {
		type: "PlutusV3",
		script: applyParamsToScript(factoryTemplate, [
			parameters.prefixHash,
			parameters.suffix,
			parameters.configLock,
		]),
	};
}
export function splitReferencePrefix(prefix: Buffer) {
	const midpoint = Math.ceil(prefix.length / 2);
	return [
		prefix.subarray(0, midpoint).toString("hex"),
		prefix.subarray(midpoint).toString("hex"),
	];
}
