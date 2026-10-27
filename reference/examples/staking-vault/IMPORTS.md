# Import and preparation phases

## Phase 1 — Select source-bound public deployments

`profiles/preprod/factory.json` records the three published factory/prefix references and
policy `9ca7570e34603c08370ac69d204ebdf9651d4b6bdd193918adc43370`.
`pool.json` records staking pool
`02f13369acbfc717f811413691d54df7aabc43ce3d8355265b298c36`.
`vault.json` and `settings.json` describe the historical second vault and committed terms.
`TRANSACTIONS.md` is the shareable address/transaction record.

Run `npm run inspect:staking` from `reference/` for an offline identity check. Archived
block confirmations are observations at the recorded time, not current UTxO availability.
The original applied staking bytes are preserved: semantically equivalent UPLC re-encoding
can change a policy ID. The current SDK's transitive UPLC encoder also differs from the one
used for the factory. This example pins parameter application locally to the historical
UPLC encoder and tests exact deployed IDs; canonical reference families are unaffected.

## Phase 2 — Choose explicit new-vault settings

Copy the public settings shape to your own file and supply:

- Explicit `Preprod` or `Preview` and its verified genesis/network domain.
- An existing source-verified staking pool, its assets, applied script bytes and reference.
- **Fresh, distinct, clean key-owned vault and position seed UTxOs**; leave the pool's
  original bootstrap parameter unchanged when importing that existing pool.
- Underlying asset equal to the pool's staked principal; reward asset comes from the pool.
- Entry/exit fees, fee recipient, virtual shares, cap, pause key and any other committed terms.
- Config/State ADA reserves computed from current minimum ADA, plus the desired buffer.
- A current chain point. The example does not invent a mainnet deployment, terms, keys or seeds.

The shipped profile's zero fees, 1,000,000 virtual share units and other values describe
that test vault only. Altering any committed field produces a different controller/certificate.

```sh
npm run vault:prepare --workspace @ctvs/staking-vault-example -- \
  /absolute/path/new-settings.json \
  /absolute/path/factory-deployment.json \
  /absolute/path/new-output-directory
```

This **offline** command verifies the recorded factory network/policy/source identity,
settings schema, pool/template parameters and immutable bindings. It exports scripts,
Config/State/expected-registration CBOR, settings, source-bound preparation and SHA-256
checksums to a new directory. It refuses to overwrite an existing directory. It does not
prove seeds/references are unspent, mint a certificate or create a vault on-chain.

## Phase 3 — Resolve chain evidence and build unsigned transactions

The application supplies a provider independently bound to the chosen network/genesis,
current protocol parameters, approved funding/collateral and freshly resolved references.
No secret is needed for this construction stage. Example API (TypeScript):

```ts
import {
  importExistingFactoryPool,
  prepareFactoryDeployment,
  readFactorySettings,
  constructFactoryVaultPublication,
  constructFactoryVaultGenesis,
  constructFactoryFirstDeposit,
  constructFactoryExistingDeposit,
  constructFactoryMint,
  constructFactoryWithdraw,
  constructFactoryRedeem,
} from "@ctvs/staking-vault-example";

// Existing deployment directory contains deployment.json and its exact plutus.json.
// This READS the existing pool; it does not initialize another one.
const imported = await importExistingFactoryPool(deploymentDirectory, provider);
const input = readFactorySettings(newPublicSettings);
const prepared = prepareFactoryDeployment({ ...input, pool: imported.prepared.settings });

// Resolve the factory/prefix references from the public factory record; verify
// exact scripts/template datums through the builders. Publish controller first.
const publication = await constructFactoryVaultPublication(
  prepared.vault, controllerReserve, creationLedger,
);
// After separately authorized publication/confirmation and fresh readback:
const genesis = await constructFactoryVaultGenesis(
  prepared.vault, freshVaultSeed, resolvedFactoryReferences,
  certificateReserve, creationLedger,
);
// After separately authorized genesis/confirmation and fresh NFT/Config resolution:
const deposit = await constructFactoryFirstDeposit(firstDepositLedger);
const topup = await constructFactoryExistingDeposit(existingDepositLedger);
const mint = await constructFactoryMint(mintLedger); // exact shares + maxAssets
const withdrawal = await constructFactoryWithdraw(withdrawLedger); // assets + maxShares
const redemption = await constructFactoryRedeem(redeemLedger); // shares
```

The argument shapes are exported by their modules in `vendor/client/src/factory/`.
`creationLedger` must include provider, funding address, explicit funding/collateral,
protected references and fee/collateral ceilings. `resolvedFactoryReferences` includes
factory, prefix0, prefix1 and controller UTxOs. First entry additionally resolves the
certificate, Config, State, pool and creation seed; later operations resolve State, pool,
position, Config and exact controller/staking references. Builders recheck immutable
preparation, all output/mint effects, final VM budgets, minimum ADA, collateral and size
including an allowance for required key witnesses. They never sign or submit.

The public snapshot's `pool.json` and `evidence/staking/blueprint.json` can be copied into an
import directory as `deployment.json` and `plutus.json`. They still require fresh provider
resolution; offline `inspect:staking` is the command for historical-only use.

## Phase 4 — Review and execution boundary

Archive unsigned CBOR, expected effects, evaluated purposes and declared/measured budgets
before any separate wallet workflow. Read back accepted Config/State/certificate NFTs after
genesis and each pool/position continuation after operations. This example contains no
live signing/submission command or automatic execution capability. Source compatibility,
public JSON and old confirmations alone do not establish present deployment readiness.
