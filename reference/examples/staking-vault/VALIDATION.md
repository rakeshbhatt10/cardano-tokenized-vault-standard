# Local validation — 27 October 2026

This record separates current local checks from historical public Preprod observations.
The example remains `deploymentReady=false`; no live transactions are authorized by these checks.

## Current checks

| Gate | Result |
| --- | --- |
| Workspace TypeScript, Biome and ESLint | Passed; structural limits unchanged |
| Example tests, source bindings and source dependency closure | 14 passed |
| Unsigned lifecycle | 14 stages; final principal backing and share supply zero |
| Factory/controller rebuild | 73 checks; six handlers match deployed program bytes/hashes/parameters |
| Staking rebuild | 254 checks; three handlers match deployed program bytes/hashes/parameters |

Run `npm run test:staking-example` for client/source/transaction checks. Run
`npm run test:staking-contracts` with both pinned compilers for fresh Aiken rebuilds/checks.
Generated reports and unsigned CBOR go under `reference/artifacts/staking-vault/`.
Source hash verification alone is never reported as recompilation.

The current staking count excludes 11 checks for the unrelated token-mint validator.
The original import's 265-check report remains historical evidence. The factory count
excludes its previously removed obsolete decoder and wallet-only helper tests. All retained
staking, admission, registration, authorization and reward tests are still run.

The full reference-workspace gate passed 665 unit/property tests, 107/130 CTVS-1/2
Aiken checks, 44 Price checks and 39 signed integration tests. Those results concern the
canonical reference packages; they do not turn the staking example into a signed/node-backed flow.

## Demonstrated accounting

All quantities below are base units; the fixture uses six decimal principal/reward tokens.

| Stage | Principal/share effect | Reward effect |
| --- | --- | --- |
| First deposit | +10,000,000 principal; +10,000,000,000,000 shares | No historic rewards acquired |
| Exact-share mint/top-up | Same principal/share increase | 6,000 units contributed for entry equalization |
| Partial withdrawal | -5,000,000 principal; burns 5,000,000,000,000 shares | Claims 12,000; pays 4,500; retains 13,500 |
| Full remaining redemption | -15,000,000 principal; burns remaining shares | Claims 6,000; pays 19,500; reserve zero |
| Re-entry | +10,000,000 principal using the same position NFT | No new position NFT or repeated registration |
| Full fixed-asset withdrawal | -10,000,000 principal; burns all shares | Claims/pays 6,000; empty position retained |

Each economic transaction evaluates all declared purposes against its final unsigned body,
checks measured/declared execution budgets, exact effects, minimum ADA, final-fee collateral
and size including witness allowance. Pool setup/notification also inspect final ledger bounds.
The synthetic pool helper uses an explicit 2,000,000-lovelace collateral floor.

Largest local publications are 16,257 estimated signed bytes against 16,384: **127 bytes of
headroom**. The fixture uses one fabricated key hash for funding/collateral/manager duties.
Additional witnesses, address changes, metadata or changed scripts require fresh size checks.
Fixture limits were not increased.

## Evidence limits and remaining work

The local ledger begins with fabricated public balances/key hashes and advances by applying
unsigned outputs. It verifies phase-two programs and client effects, not signatures or node
acceptance. [Preprod records](profiles/preprod/TRANSACTIONS.md) are historical observations;
`inspect:staking` reproduces their identities offline without claiming fresh UTxO availability.

First position creation is demonstrated through deposit; exact-share mint currently uses an
existing position. A separate nonempty-pool fixture verifies principal-delta accounting, but
full joint wallet-plus-two-vault transaction histories remain pending. Other remaining work
is independent security review, operational recovery and node-backed acceptance of this harness.
Fresh network/genesis, protocol parameters, funding and reference resolution are required
before constructing any separately authorized live transaction.
