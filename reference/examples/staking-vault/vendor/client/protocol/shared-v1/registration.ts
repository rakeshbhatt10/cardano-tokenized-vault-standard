import { record, type Wire } from "./authorization.ts";
export const SUPPORTED_IMPLEMENTATION =
	"43545653312d4d495845442d464143544f52592d31";
export interface Registration {
	version: 1n;
	controller: string;
	statePolicy: string;
	stateName: "5354415445";
	implementation: typeof SUPPORTED_IMPLEMENTATION;
	instanceHash: string;
	configHash: string;
}
const hex = (v: Wire, n?: number) => {
	if (!(v instanceof Uint8Array) || (n !== undefined && v.length !== n))
		throw Error("Invalid registration bytes");
	return Array.from(v, (b) => b.toString(16).padStart(2, "0")).join("");
};
/** Format/profile validation only. Factory NFT provenance is a separate mandatory check. */
export function decodeRegistration(raw: Wire): Registration {
	const r = record(raw);
	if (r.constr !== 0n || r.fields.length !== 7 || r.fields[0] !== 1n)
		throw Error("Unsupported registration version/shape");
	const f = r.fields,
		controller = hex(f[1]!, 28),
		statePolicy = hex(f[2]!, 28),
		stateName = hex(f[3]!),
		implementation = hex(f[4]!);
	if (
		controller !== statePolicy ||
		stateName !== "5354415445" ||
		implementation !== SUPPORTED_IMPLEMENTATION
	)
		throw Error("Unsupported controller implementation or State identity");
	return {
		version: 1n,
		controller,
		statePolicy,
		stateName,
		implementation,
		instanceHash: hex(f[5]!, 32),
		configHash: hex(f[6]!, 32),
	};
}
