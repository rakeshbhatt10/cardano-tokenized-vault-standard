# Source provenance and reproducibility

The example was imported from the workshop's tested staking vault and the staking
protocol handoff on 27 October 2026. It runs independently of both sibling checkouts.
Canonical CTVS modules are reused from this repository's `reference/packages/`.

## Current source layout

- `onchain/factory/`: authenticated factory, controller entrypoint and Config lock.
- `onchain/vault/lib/`: current staking adapter and vault State accounting/validation.
- `onchain/staking/`: staking pool validator, protocol libraries and their tests.
- `vendor/client/`: the TypeScript dependency closure used by the facade, commands and tests.
- `docs/`: current authorization guide and canonical interface specification.
- `profiles/preprod/`: public historical deployment/transaction records.
- `evidence/`: imported attestations and baseline artifacts used for identity/ABI verification.

The copied Deno wallet/token/admin CLI, unrelated test-token validator, duplicate client-side
Aiken sources and unreachable TypeScript modules are not part of the current example.
Their original source is recoverable from the pinned staking source archive where applicable.
Signing, submission and wallet-generation commands are not exposed by this package.

## Factory/controller bindings

`evidence/factory/build.json` is the immutable deployed-build attestation, SHA-256
`3df02869565300878e93bcf267e1ed09367388a0e094ff2268e8d58c2b36e4fa`.
Its original blueprint SHA-256 is
`94354b21743742d9afaaf3f07174ceeb73ed21cf7a9afa66017fd47f7138525b`.

`source-selection.json` records current path/hash bindings, original source labels and
omitted source hashes/reasons. Its hash is pinned in the verifier. Current names include
`staking/` and `staking_ctvs1/staking_state.ak`; outdated unused adapter types are removed.
The original editor swap is excluded explicitly. Original source labels never become
arbitrary filesystem paths.

Rebuilds stage canonical shared modules, generate the Config-lock binding and controller
vector adapter, then require exactly six retained handlers. Every compiled program, script
hash and parameter schema must match the original blueprint. Removing unrelated validators
and definitions changes the whole blueprint hash; that is not represented as whole-file equality.
The old build script is integrity-checked provenance data, not a runnable example command.

## Staking bindings

`evidence/staking/import-snapshot.json` is the unchanged import attestation, SHA-256
`52c966c171f82f16f83bf4bbee12570e01ebb6c74d5868be96658dd308fceeb2`.
The original deployed-template blueprint is `evidence/staking/blueprint.json`, SHA-256
`ab0634037969b891bde01da7082cc51bb1ecbd2c31a8f21cfa0488a98d00cfcb`.
The source archive, upstream build record and imported interface remain baseline evidence.

`onchain/staking/snapshot.json` binds the current compiler inputs and external evidence/docs.
Its hash is pinned by `STAKING_SNAPSHOT_SHA256`. Removed and relocated import paths are
recorded explicitly. The original staking build included a separate token-mint policy; the
current build contains only the three staking handlers. Each must match the original
compiled program, hash and parameter schema. The pool's deployed bytes/policy are preserved.

The imported check reports describe their original source inventories. Fresh reports under
`reference/artifacts/staking-vault/contracts/` describe the current **73 factory/controller**
and **254 staking** checks. Historical reports are not relabelled as current checks.

## Client and ABI

`provenance.json` records original/ported client hashes, removed files and the exact current
client inventory. All active client modules are reachable from public exports, commands or
tests. The client enables unused-local/parameter checks. Imported code has narrow style
exclusions; new orchestration/tests follow the workspace style and structural rules.

The example pins parameter application to `@harmoniclabs/uplc@1.2.4` and
`plutus-data@1.2.4`: a newer encoder can normalize equivalent UPLC and change script hashes.
These dependencies are local to the example. Canonical reference packages keep their versions.

`docs/STAKING-INTERFACE.json`, TypeScript codecs, current Aiken codecs/tests and golden CBOR
vectors describe the same ABI. The published identifier `CTVS1-MIXED-FACTORY-1`, imported
`mixed-owner-v1` build identifier and historical source labels retain their committed values;
current module/document names use staking terminology. Renaming a committed identifier would
select a different deployment. Registration versions and exact datum/redeemer fields are unchanged.

Original source notices and Apache-2.0 project metadata are retained; importing does not
relicense source. Development followed `skills/write-validator/SKILL.md` and
`skills/build-transaction/SKILL.md` from the workshop's pinned Cardano skill bundle and its
bundled Aiken module/UPLC documentation. Upstream references:
[Aiken](https://aiken-lang.org/), [CIP-31](https://cips.cardano.org/cip/CIP-0031),
[CIP-33](https://cips.cardano.org/cip/CIP-0033).
