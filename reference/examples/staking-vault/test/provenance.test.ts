import assert from "node:assert/strict";
import test from "node:test";
import { verifyImportedSources } from "../src/verify-import.ts";

test("all imported client and contract sources retain explicit hash bindings", () => {
  const result = verifyImportedSources();

  assert.equal(result.verifiedImportedBytes, true);
  assert.equal(result.recompiledThisRun, false);
});
