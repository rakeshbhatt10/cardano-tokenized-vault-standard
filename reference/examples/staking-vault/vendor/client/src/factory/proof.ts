/** Current authenticated factory, source verification and controller layout. */
import {
	validatorToAddress,
	validatorToScriptHash,
	type Script,
} from "@lucid-evolution/lucid";
import { readVerifiedFactoryBuild } from "./proof/build.ts";
import {
	selectFactoryTemplates,
	deriveControllerLayout,
	prepareFactoryPolicyParameters,
	applyFactoryPolicyParameters,
	splitReferencePrefix,
	type FactoryProofMode,
} from "./proof/scripts.ts";

export { blake, dataHash, rawScript } from "./proof/hashing.ts";

/** Verify the pinned build, select its approved template and apply factory params. */
export function loadFactoryProof(mode: FactoryProofMode = "staking-vault") {
	const { manifest, blueprint, buildId, activeSources, sourceSelectionSha256 } = readVerifiedFactoryBuild();
	const templates = selectFactoryTemplates(blueprint, mode);
	const layout = deriveControllerLayout(templates.controllerTemplate);
	const lock: Script = { type: "PlutusV3", script: templates.lockTemplate };
	if (validatorToScriptHash(lock) !== manifest.configLock)
		throw Error("Factory lock mismatch");
	const parameters = prepareFactoryPolicyParameters(
		layout,
		manifest.configLock,
	);
	const script = applyFactoryPolicyParameters(
		templates.factoryTemplate,
		parameters,
	);
	return {
		manifest,
		sourceHashes: activeSources,
		sourceSelectionSha256,
		controllerTemplate: templates.controllerTemplate,
		prefix: layout.prefix,
		suffix: layout.suffix,
		parts: splitReferencePrefix(layout.prefix),
		script,
		policy: validatorToScriptHash(script),
		lock,
		lockAddress: validatorToAddress("Preview", lock),
		buildId,
		mode,
		scope: "source-bound factory staking-vault program",
	};
}

