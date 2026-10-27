/** Dependency-free source contract shared with the Deno staking repository. */
export type Wire =
	| bigint
	| Uint8Array
	| Wire[]
	| { constr: number | bigint; fields: Wire[] }
	| { map: [Wire, Wire][] };
export type Ref = { txId: string; index: bigint };
export type Authorization =
	| {
			kind: "staking";
			version: 1n;
			poolId: string;
			positionName: string;
			operation: "stake" | "withdraw_and_claim";
			amount: bigint;
			creationRef: Ref | null;
			stateOutput: bigint;
			base: Wire;
			maxRewardInput: bigint;
			minRewardOutput: bigint;
	  }
	| { kind: "maintenance"; version: 1n; base: Wire };
export const MAX_Q = 9223372036854775807n;
const fail = (reason: string): never => {
	throw new Error("Staking authorization: " + reason);
};
const q = (v: Wire, positive = false): bigint =>
	typeof v === "bigint" && v >= (positive ? 1n : 0n) && v <= MAX_Q
		? v
		: fail("invalid quantity");
const idx = (v: Wire): bigint =>
	q(v) <= 65535n ? (v as bigint) : fail("invalid output index");
export const tag = (constr: number, fields: Wire[]): Wire => ({
	constr,
	fields,
});
const hex = (v: Wire, bytes: number): string =>
	v instanceof Uint8Array && v.length === bytes
		? Array.from(v, (b) => b.toString(16).padStart(2, "0")).join("")
		: fail("invalid identity length");
const bytes = (s: string, length: number): Uint8Array =>
	new RegExp(`^[0-9a-f]{${length * 2}}$`).test(s)
		? Uint8Array.from(s.match(/../g)!.map((b) => parseInt(b, 16)))
		: fail("invalid identity hex");
export function record(v: Wire): { constr: bigint; fields: Wire[] } {
	if (
		typeof v !== "object" ||
		v === null ||
		!("constr" in v) ||
		!Array.isArray(v.fields) ||
		!(typeof v.constr === "bigint" || Number.isSafeInteger(v.constr))
	)
		return fail("expected constructor");
	return { constr: BigInt(v.constr), fields: v.fields };
}
const exact = (v: Wire, t: number, n: number) => {
	const r = record(v);
	if (r.constr !== BigInt(t) || r.fields.length !== n)
		fail("constructor/field count mismatch");
	return r.fields;
};
export function baseInfo(base: Wire) {
	const e = exact(base, 0, 3);
	if (hex(e[0]!, 4) !== "43545653" || e[1] !== 2n)
		fail("invalid CTVS envelope");
	const a = record(e[2]!);
	const n = Number(a.constr);
	if (n >= 0 && n <= 3) {
		if (a.fields.length !== 5) fail("invalid user action");
		q(a.fields[1]!, true);
		q(a.fields[2]!, true);
		const stateOutput = idx(a.fields[3]!);
		const receiverOutput = idx(a.fields[4]!);
		if (stateOutput === receiverOutput) fail("overlapping outputs");
		return { tag: n, stateOutput, receiverOutput, entry: n < 2 };
	}
	if (n >= 5 && n <= 7) {
		if (a.fields.length !== 2) fail("invalid maintenance action");
		const stateOutput = idx(a.fields[n === 5 ? 0 : 1]!);
		if (n === 5) idx(a.fields[1]!);
		else if (n === 6) q(a.fields[0]!, true);
		else if (
			typeof a.fields[0] !== "bigint" ||
			a.fields[0] < 0n ||
			a.fields[0] > 3n
		)
			fail("invalid pause flags");
		return { tag: n, stateOutput, entry: false };
	}
	return fail("unsupported action");
}
export function decodeAuthorization(raw: Wire): Authorization {
	const outer = record(raw);
	if (outer.constr === 1n) {
		const f = exact(raw, 1, 2);
		if (f[0] !== 1n) fail("unsupported version");
		if (baseInfo(f[1]!).tag < 5) fail("user action in maintenance");
		return { kind: "maintenance", version: 1n, base: f[1]! };
	}
	const f = exact(raw, 0, 10);
	if (f[0] !== 1n) fail("unsupported version");
	const poolId = hex(f[1]!, 28),
		positionName = hex(f[2]!, 32),
		op = record(f[3]!);
	if (op.fields.length || !(op.constr === 0n || op.constr === 1n))
		fail("invalid operation");
	const amount = q(f[4]!, true),
		option = record(f[5]!);
	let creationRef: Ref | null = null;
	if (option.constr === 0n) {
		const [ref] = exact(f[5]!, 0, 1),
			r = exact(ref!, 0, 2);
		creationRef = { txId: hex(r[0]!, 32), index: idx(r[1]!) };
	} else exact(f[5]!, 1, 0);
	const stateOutput = idx(f[6]!),
		base = f[7]!,
		maxRewardInput = q(f[8]!),
		minRewardOutput = q(f[9]!);
	const info = baseInfo(base);
	if (
		info.tag > 3 ||
		info.entry !== (op.constr === 0n) ||
		info.stateOutput !== stateOutput
	)
		fail("action/operation/continuation mismatch");
	if (
		(info.entry && minRewardOutput !== 0n) ||
		(!info.entry && (maxRewardInput !== 0n || creationRef !== null))
	)
		fail("invalid operation bounds or creation mode");
	return {
		kind: "staking",
		version: 1n,
		poolId,
		positionName,
		operation: op.constr === 0n ? "stake" : "withdraw_and_claim",
		amount,
		creationRef,
		stateOutput,
		base,
		maxRewardInput,
		minRewardOutput,
	};
}
export function encodeAuthorization(a: Authorization): Wire {
	if (a.kind !== "maintenance" && a.kind !== "staking")
		fail("unknown envelope role");
	if (
		a.kind === "staking" &&
		a.operation !== "stake" &&
		a.operation !== "withdraw_and_claim"
	)
		fail("unknown operation");
	const wire =
		a.kind === "maintenance"
			? tag(1, [a.version, a.base])
			: tag(0, [
					a.version,
					bytes(a.poolId, 28),
					bytes(a.positionName, 32),
					tag(a.operation === "stake" ? 0 : 1, []),
					a.amount,
					a.creationRef
						? tag(0, [
								tag(0, [bytes(a.creationRef.txId, 32), a.creationRef.index]),
							])
						: tag(1, []),
					a.stateOutput,
					a.base,
					a.maxRewardInput,
					a.minRewardOutput,
				]);
	decodeAuthorization(wire);
	return wire;
}

/** Eighth v1 pool parameter: immutable Option<FactoryPolicy>, never a per-vault allowlist. */
export function factoryTrustParameter(
	vaultSupported: boolean,
	policy: string | null,
): Wire {
	if (!vaultSupported) {
		if (policy !== null)
			fail("wallet-only pool must have no factory trust anchor");
		return tag(1, []);
	}
	if (policy === null)
		return fail("vault-supported pool needs an explicit factory policy");
	return tag(0, [bytes(policy, 28)]);
}

/** Existing staking action tags 0..9 are preserved; combined exit is tag 10. */
export function stakingAction(a: Authorization): Wire {
	if (a.kind !== "staking")
		return fail("maintenance cannot authorize a staking action");
	encodeAuthorization(a);
	return a.operation === "stake"
		? tag(0, [
				a.amount,
				bytes(a.positionName, 32),
				a.creationRef
					? tag(0, [
							tag(0, [bytes(a.creationRef.txId, 32), a.creationRef.index]),
						])
					: tag(1, []),
			])
		: tag(10, [a.amount, bytes(a.positionName, 32)]);
}
