import { createHash } from "node:crypto";
import { blake2b } from "@noble/hashes/blake2.js";
import { CML, Data, withCMLScope } from "@lucid-evolution/lucid";

/** Build/source fingerprints use SHA-256; these are not Cardano policy IDs. */
export const sha256 = (bytes: Uint8Array) =>
	createHash("sha256").update(bytes).digest("hex");
/** Blake2b-256 for commitments, or Blake2b-224 when length is explicitly 28. */
export const blake = (bytes: Uint8Array, length = 32) =>
	Buffer.from(blake2b(bytes, { dkLen: length })).toString("hex");
/** Hash canonical Plutus Data using the SDK's pinned ledger implementation. */
export const dataHash = (data: Data) =>
	withCMLScope((own) =>
		own(
			CML.hash_plutus_data(own(CML.PlutusData.from_cbor_hex(Data.to(data)))),
		).to_hex(),
	);
/** Remove the outer script-CBOR wrapper; keep the exact bytes hashed by Cardano. */
export const rawScript = (script: string) =>
	withCMLScope((own) =>
		Buffer.from(own(CML.PlutusV3Script.from_cbor_hex(script)).to_raw_bytes()),
	);
