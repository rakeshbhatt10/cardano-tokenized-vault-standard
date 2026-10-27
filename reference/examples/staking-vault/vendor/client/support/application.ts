import { Application, UPLCConst, UPLCProgram, encodeUPLC, parseUPLC } from "@harmoniclabs/uplc";
import { dataFromCbor } from "@harmoniclabs/plutus-data";
import { applyDoubleCborEncoding, Data } from "@lucid-evolution/lucid";
import { decode } from "cbor-x";

/** Match the deployed controller's Flat encoding. SDK transitive UPLC upgrades
 * can normalize case/constr encodings and therefore change every script hash.
 * This example pins the historical encoder locally; canonical families use
 * their existing SDK. Existing pool bytes are checked and preserved separately. */
export function applyParamsToScript(script: string, parameters: Data[]): string {
  const flat = decode(decode(Buffer.from(applyDoubleCborEncoding(script), "hex")));
  const program = parseUPLC(flat, "flat");
  const body = parameters.reduce(
    (term, parameter) => new Application(term, UPLCConst.data(dataFromCbor(Data.to(parameter)))),
    program.body,
  );
  return applyDoubleCborEncoding(
    Buffer.from(encodeUPLC(new UPLCProgram(program.version, body)).toBuffer().buffer).toString("hex"),
  );
}
