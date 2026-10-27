import { applyParamsToScript } from "../../support/application.ts";
import {
	
	Constr,
	Data,
	validatorToAddress,
	validatorToScriptHash,
	type Script,
} from "@lucid-evolution/lucid";
import {
	encodeData,
	hex,
	termsData,
	termsHash,
	outRefData,
} from "@ctvs/protocol";
import { buildGenesisPlan } from "../../../../../../implementations/ctvs1/client/src/genesis.ts";
import { poolBindingData, type VaultSetup } from "../setup/vault.ts";
import { loadFactoryProof, dataHash, blake, rawScript } from "./proof.ts";
export type FactoryVaultSetup = Omit<
	VaultSetup,
	"bindingAuthority" | "implementation"
>;
export const FACTORY_IMPLEMENTATION = Buffer.from(
	"CTVS1-MIXED-FACTORY-1",
).toString("hex");
/** Automatic genesis candidate; no authority field, fallback signature or admission API. */
export function prepareFactoryVault(input: FactoryVaultSetup) {
	if ("bindingAuthority" in input || "implementation" in input)
		throw Error("Factory creation has no privileged binding authority");
	const publicKeys = [
		"network",
		"terms",
		"seed",
		"configReserve",
		"stateReserve",
		"chainPoint",
		"poolBinding",
	];
	if (Object.keys(input).some((key) => !publicKeys.includes(key)))
		throw new Error("Unknown factory settings field");
	if (input.network !== "Preview" && input.network !== "Preprod")
		throw Error("Explicit test network required");
	const source = loadFactoryProof("staking-vault"),
		binding = poolBindingData(input.poolBinding);
	const settings = new Constr(0, [
		Data.from<Data>(hex(encodeData(termsData(input.terms)))),
		Data.from<Data>(hex(encodeData(binding))),
	]);
	const seed = Data.from<Data>(hex(encodeData(outRefData(input.seed))));
	const instance = new Constr(0, [1n, seed, dataHash(settings)]),
		instanceHash = dataHash(instance);
	const script: Script = {
		type: "PlutusV3",
		script: applyParamsToScript(source.controllerTemplate, [instanceHash]),
	};
	const controller = validatorToScriptHash(script);
	const reconstructed = Buffer.concat([
		source.prefix,
		Buffer.from(instanceHash, "hex"),
		source.suffix,
	]);
	if (
		!reconstructed.equals(rawScript(script.script)) ||
		blake(Buffer.concat([Buffer.from([3]), reconstructed]), 28) !== controller
	)
		throw Error("Factory controller hash mismatch");
	if (
		input.terms.underlying === "ada" ||
		input.terms.profile !== 0n ||
		input.terms.executionModes !== 3n ||
		input.poolBinding.poolPolicy === controller
	)
		throw Error("Require native staking configuration");
	const commitment = termsHash(input.terms);
	const deployment = {
		family: "ctvs1" as const,
		network: input.network,
		networkDomain: input.terms.networkDomain,
		policy: controller,
		configLock: validatorToScriptHash(source.lock),
		claimScript: null,
		termsHash: commitment,
		configRef: input.seed,
		buildId: source.buildId,
		chainPoint: input.chainPoint,
	};
	const plan = buildGenesisPlan({ ...input, deployment });
	const configData = new Constr(0, [
		Data.from<Data>(hex(encodeData(plan.outputs[0]!.datum!))),
		Data.from<Data>(hex(encodeData(binding))),
	]);
	const stateData = Data.from<Data>(hex(encodeData(plan.outputs[1]!.datum!)));
	const configHash = dataHash(configData);
	const registration = new Constr(0, [
		1n,
		controller,
		controller,
		"5354415445",
		FACTORY_IMPLEMENTATION,
		instanceHash,
		configHash,
	]);
	const scriptBytes = script.script.length / 2;
	const localPublicationLimit = 16384;
	const witnessAllowance = 128;
	return {
		publicationAssessment: {
			scriptBytes,
			witnessAllowance,
			localPublicationLimit,
			canPublish: scriptBytes + witnessAllowance < localPublicationLimit,
			note: "Necessary size check only; transaction outputs/body add more bytes",
		},
		blockers: [
			"Full joint wallet/two-vault lifecycle and independent review remain pending",
			"Fresh network/genesis, UTxO, reference and transaction-limit verification is required",
		],
		schema: "FACTORY-STAKING-VAULT-PREPARATION-1" as const,
		input,
		source,
		instance,
		instanceHash,
		script,
		controller,
		address: validatorToAddress(input.network, script),
		configData,
		stateData,
		registration,
		configHash,
		stateUnit: controller + "5354415445",
		configUnit: controller + "4944",
		certificateUnit: source.policy + controller,
		requiredPrivilegedSigners: [],
		admissionEvidenceVerified: false,
		stakingIntegrated: false,
		deploymentReady: false,
		executionEnabled: false,
	};
}
