import { applyParamsToScript } from "../../support/application.ts";
import { z } from "zod";
import {
	
	validatorToScriptHash,
	type Script,
} from "@lucid-evolution/lucid";

export const existingPoolProgramSchema = z
	.object({
		policy: z.string().regex(/^[0-9a-f]{56}$/),
		blueprintSha256: z.string().regex(/^[0-9a-f]{64}$/),
		script: z
			.object({
				type: z.literal("PlutusV3"),
				script: z.string().regex(/^(?:[0-9a-f]{2})+$/),
			})
			.strict(),
		reference: z
			.object({
				txHash: z.string().regex(/^[0-9a-f]{64}$/),
				outputIndex: z
					.string()
					.regex(/^(0|[1-9][0-9]{0,9})$/)
					.refine((v) => BigInt(v) <= 4294967295n),
			})
			.strict(),
	})
	.strict();

export type ExistingPoolProgram = z.infer<typeof existingPoolProgramSchema>;

/** Check the decoded program against the approved template/parameters, but keep
 * the original bytes: UPLC re-encoding can change the ledger's script identity.
 * Live existence/ownership is checked separately; this function is offline. */
export function selectExistingPoolProgram(
	input: ExistingPoolProgram,
	derived: Script,
	blueprintSha256: string,
): Script {
	const saved = existingPoolProgramSchema.parse(input);
	if (
		saved.blueprintSha256 !== blueprintSha256 ||
		validatorToScriptHash(saved.script) !== saved.policy ||
		applyParamsToScript(saved.script.script, []) !== derived.script
	)
		throw Error("Existing staking program/template/parameters mismatch");
	return saved.script;
}
