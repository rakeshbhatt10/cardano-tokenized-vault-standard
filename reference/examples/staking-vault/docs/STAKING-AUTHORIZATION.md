# Staking authorization and registration

This is the current integration documentation. The [interface specification](STAKING-INTERFACE.json)
records exact constructors, field order, action tags and versions. The [validation record](../VALIDATION.md)
distinguishes demonstrated behavior from pending acceptance work.

## Two separate proofs

**Registration recognizes the controller at first position creation.** The pool permanently
commits to the authenticated factory policy. First entry references the genuine certificate
NFT and immutable Config ID. Their identities bind the controller, its existing State NFT,
implementation version, Config commitment, pool, position seed and assets. A JSON file or a
correctly shaped datum cannot replace the certificate NFT. Registration has no manual
per-vault approval key.

**A consumed State authorizes each operation.** Stake, top-up, withdrawal and redemption
consume the controller State, preserve its unique NFT and create the required continuation.
The version 1 envelope binds the pool, position, operation, principal delta, optional creation
seed, State output, inner vault action and reward bounds. Position datum version 2 is a
separate version from authorization envelope version 1.

An existing position's valid top-up or exit does not require a repeated certificate lookup,
registry approval or a factory signature. The controller continues to authenticate its exact
immutable Config and custody binding.

## Responsibilities in one composed transaction

- The staking program validates the position owner, principal delta, pool totals, reward
  checkpoints, liabilities, identity NFTs and required pool/position continuations.
- The executing registered vault controller validates State/Config, share issuance or burn,
  fees, entry equalization, receiver bounds and exact principal/reward payouts. Its libraries
  are compiled into the controller; they are not separately invoked contracts.
- The strict shared codecs and golden CBOR vectors bind both sides to the same envelope.
  Maintenance authorization cannot authorize staking or an exit.

A pool that supports vaults is permanently unlocked and identifies an explicit factory.
Wallet positions use wallet-key authorization; vault positions use the admitted controller
and authenticated State. These are ownership variants of the current staking protocol.

## Principal entry and exit

Deposit specifies principal input; exact-share mint specifies shares and a maximum principal
input. Entry uses staking action `Stake` and preserves position-specific reward accounting.
New shares contribute bounded reward equalization so they do not dilute existing holders.

Withdraw specifies principal output and a maximum share burn; redeem specifies shares.
Both compose staking action **`WithdrawAndClaim` (tag 10)**. Staking settles this position's
principal and earned rewards. The controller distributes the shareholder entitlement and
preserves remaining shareholders' reward reserves. Full redemption retains the empty
position and its NFT for re-entry.

Standalone vault Withdraw/Claim, vault position closure and position NFT burns are
unsupported. The registered-controller profile requires distinct principal and reward assets.

## Deployment evidence and compatibility

The [public Preprod record](../profiles/preprod/TRANSACTIONS.md) contains confirmed historical
factory, vault and operation transactions. The local example constructs and evaluates a full
unsigned lifecycle against the actual compiled programs. Neither historical confirmations nor
local unsigned checks establish current UTxO availability or independent security approval.

The deployed implementation identifier `CTVS1-MIXED-FACTORY-1` retains its exact bytes because
it is authenticated by registration. Current source/document names use staking terminology.
Changing the committed identifier would describe a different deployment.

Independent review, full joint wallet-plus-two-vault transaction histories and node-backed
acceptance of the new local harness remain pending. Overall readiness and execution flags
remain false.
