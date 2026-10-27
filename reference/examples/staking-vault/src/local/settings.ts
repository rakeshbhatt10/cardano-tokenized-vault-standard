import { readFileSync } from "node:fs";
import { readFactorySettings } from "../../vendor/client/src/setup/composed-settings.ts";
import { prepareFactoryDeployment } from "../index.ts";
import type { LocalLedger } from "./ledger.ts";

/** Explicit fixture terms, unrelated to any live wallet or reusable deployment seed. */
export function localSettings(ledger: LocalLedger) {
  const historical = readFactorySettings(
    JSON.parse(
      readFileSync(new URL("../../profiles/preprod/settings.json", import.meta.url), "utf8"),
    ),
  );
  const { deployedProgram: _deployed, ...pool } = historical.pool;

  const seed = (byte: string) => ({ txId: byte.repeat(32), index: 0n });

  return prepareFactoryDeployment({
    pool: {
      ...pool,
      network: "Preview",
      fundingAddress: ledger.address,
      bootstrapRef: { txHash: "ab".repeat(32), outputIndex: "0" },
      manager: "12".repeat(28),
      rewardsDistributor: "12".repeat(28),
      poolReserveLovelace: "5000000",
      referenceReserveLovelace: "100000000",
    },
    vault: {
      ...historical.vault,
      network: "Preview",
      seed: seed("ac"),
      configReserve: 5_000_000n,
      stateReserve: 5_000_000n,
      chainPoint: { slot: 0n, blockHash: "00".repeat(32) },
      terms: {
        ...historical.vault.terms,
        networkDomain: "34".repeat(32),
        pauseKey: null,
        feeDestination: {
          address: { payment: { type: "key", hash: "12".repeat(28) }, stake: null },
          datum: null,
        },
      },
    },
    positionSeed: seed("ad"),
  });
}
