import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { runLocalLifecycle } from "./local/lifecycle.ts";

const result = await runLocalLifecycle();
const directory = resolve(process.argv[2] ?? "artifacts/staking-vault/local");

await mkdir(directory, { recursive: true });

for (const record of result.records)
  await writeFile(resolve(directory, `${record.stage}.unsigned.cbor`), `${record.cbor}\n`);

await writeFile(
  resolve(directory, "evidence.json"),
  JSON.stringify(result, (_, value) => (typeof value === "bigint" ? String(value) : value), 2) +
    "\n",
);
console.log(
  JSON.stringify(
    {
      directory,
      stages: result.records.map((r) => r.stage),
      finalBacking: String(result.finalBacking),
      finalSupply: String(result.finalSupply),
      synthetic: true,
      signed: false,
      submitted: false,
      deploymentReady: false,
    },
    null,
    2,
  ),
);
