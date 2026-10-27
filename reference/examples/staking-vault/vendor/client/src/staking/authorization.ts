import {
	decodeAuthorization,
	encodeAuthorization,
	type Authorization,
} from "../../protocol/shared-v1/authorization.ts";
export { decodeAuthorization, encodeAuthorization, type Authorization };
export const stakingAuthorization = (
	a: Omit<Extract<Authorization, { kind: "staking" }>, "kind" | "version">,
) => encodeAuthorization({ kind: "staking", version: 1n, ...a });
export const maintenanceAuthorization = (base: Authorization["base"]) =>
	encodeAuthorization({ kind: "maintenance", version: 1n, base });
