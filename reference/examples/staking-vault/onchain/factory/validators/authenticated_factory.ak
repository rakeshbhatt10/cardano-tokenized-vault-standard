// Factory minting policy for the actual CTVS-1 staking-vault implementation.
//
// One vault-creation transaction executes TWO minting policies:
//   1. The approved vault controller mints its ID and STATE identity tokens.
//   2. This factory mints one registration certificate for that controller.
// Both policies must succeed. The controller checks its complete genesis rules;
// this factory proves that the controller is an instance of the approved template
// and that its certificate commits to the matching Config and State identities.
//
// Publishing this program as a reference script does not run this mint handler.
// It runs later when a transaction mints a registration certificate under it.

// Low-level Plutus operations, including deterministic Data serialization.
use aiken/builtin
// Search transaction inputs/outputs and require exact matching lists.
use aiken/collection/list
// 224-bit hash: Cardano script/policy identity. 256-bit hash: data commitments.
use aiken/crypto.{blake2b_224, blake2b_256}
// Join the script-template bytes and inspect their lengths.
use aiken/primitive/bytearray
// Construct a script address with this payment script hash and no stake part.
use cardano/address.{from_script}
// Build and compare exact multi-asset values and mint quantities.
use cardano/assets
// InlineDatum carries the actual Data; Transaction is the ledger-provided context.
use cardano/transaction.{InlineDatum, Transaction}
// Decode the public CTVS State datum using its expected wire constructor/fields.
use ctvs/decode
// State record decoded from the authenticated vault continuation.
use ctvs/wire.{State}
// Read the extended Config and recompute its seed/Terms/pool-binding commitment.
use factory/controller as instance_controller
// Register is the caller's redeemer; Registration is the certificate's datum.
use factory/types.{Register, Registration}

// These parameters are fixed when the factory script is applied off-chain.
// Together they select one approved controller template and its permanent lock.
// Each vault can register automatically by satisfying the checks below; there is
// no privileged per-vault approval signature or mutable registration authority.
validator authenticated_factory(
  // Commitment to the approved script prefix, supplied in two reference datums.
  prefix_hash: ByteArray,
  // Exact bytes after the controller's fixed-width instance-hash parameter.
  suffix: ByteArray,
  // Spending-script hash whose always-failing validator locks Config/certificates.
  config_lock: ByteArray,
) {
  // raw: untrusted registration redeemer supplied by the transaction builder.
  // policy: THIS factory's policy ID, supplied by the ledger for this mint purpose.
  // tx: the actual transaction, including consumed/reference inputs and all mints.
  mint(raw: Data, policy: ByteArray, tx: Transaction) {
    // Decode the registration instructions: instance, template references and
    // the three proposed output indices. Decode failure rejects the transaction.
    expect registration: Register = raw
    // Accept only the supported instance format.
    expect registration.instance.version == 1
    // The creation seed's output index must fit the supported reference profile.
    expect
      registration.instance.seed.output_index >= 0 && registration.instance.seed.output_index <= 65535
    // A Cardano transaction ID is 32 bytes.
    expect bytearray.length(registration.instance.seed.transaction_id) == 32
    // The settings commitment is a 32-byte hash, not the settings themselves.
    expect bytearray.length(registration.instance.settings_hash) == 32

    // Find exactly one referenced UTxO for the first template part. The singleton
    // pattern [first] rejects both missing and duplicate matches. Reference inputs
    // are read without being consumed, so other vault creations can reuse them.
    expect [first] = list.filter(
      tx.reference_inputs,
      fn(i) { i.output_reference == registration.first_part },
    )
    // Resolve the second part independently, with the same uniqueness requirement.
    expect [second] = list.filter(
      tx.reference_inputs,
      fn(i) { i.output_reference == registration.second_part },
    )
    // One UTxO cannot be presented as both template parts.
    expect registration.first_part != registration.second_part
    // Both parts must contain inline data; a datum hash alone is insufficient.
    expect InlineDatum(first_raw) = first.output.datum
    expect InlineDatum(second_raw) = second.output.datum
    // Each inline datum must decode as a byte array containing template bytes.
    expect a: ByteArray = first_raw
    expect b: ByteArray = second_raw
    // Reject empty parts and bound each part to 16 KiB. Actual transactions must
    // independently satisfy ledger limits for storing/referencing these outputs.
    expect bytearray.length(a) > 0 && bytearray.length(a) <= 16384
    expect bytearray.length(b) > 0 && bytearray.length(b) <= 16384
    // Reassemble the prefix in its committed order: first part, then second part.
    let prefix = bytearray.concat(a, b)
    // Authenticate the bytes against the factory parameter. A copied reference
    // with identical bytes is acceptable; substituted template bytes must fail.
    expect blake2b_256(prefix) == prefix_hash

    // Commit to this vault instance: version, unique creation seed and settings
    // hash. This uses Plutus Data serialization, not JSON serialization.
    let instance_hash = blake2b_256(
      builtin.serialise_data(registration.instance),
    )
    // Reconstruct this instance's controller identity using the exact fixed-width
    // script layout established by the off-chain compiler/SDK build checks:
    //   script hash = blake2b_224(Plutus V3 tag || prefix || instance hash || suffix)
    // The prefix/suffix contain the required serialized-script wrapper bytes.
    let controller = blake2b_224(
      bytearray.concat(
        // Cardano's Plutus V3 language tag prefixes the script bytes for hashing.
        #"03",
        bytearray.concat(prefix, bytearray.concat(instance_hash, suffix)),
      ),
    )
    // The vault's identity policy must be distinct from its certificate factory.
    expect controller != policy
    // The seed must be a CONSUMED input, not merely a reference input. A UTxO can
    // be consumed once, making this instance's creation one-shot. The reusable
    // factory can still register different instances with different seeds.
    expect
      list.any(
        tx.inputs,
        fn(i) { i.output_reference == registration.instance.seed },
      )

    // Resolve the proposed Config output. Output indices are only hints: its
    // datum, address and token/value contents are all checked below.
    expect Some(config_output) = list.at(tx.outputs, registration.config_output)
    // Require the complete Config data on the output itself.
    expect InlineDatum(config_raw) = config_output.datum
    // Decode the extended Config and recompute its instance commitment from its
    // actual seed, Terms and pool binding. Matching instance_hash binds these
    // settings to the approved controller instance. Full semantic validation of
    // Terms/binding/accounting is also enforced by that controller's genesis.
    let instance_controller.ConfigView { vault_policy, seed, .. } = instance_controller.resolve_config(
      config_output,
      instance_hash,
    )
    // Config must name the derived vault policy and the seed consumed above.
    expect vault_policy == controller && seed == registration.instance.seed
    // Store Config at the permanent lock, whose spending handler always fails.
    expect config_output.address == from_script(config_lock)
    // A Config output is data/identity custody; it must carry no reference script.
    expect config_output.reference_script == None
    // Require exactly its existing ADA plus ONE controller.ID token. Equality
    // rejects every other native asset. This does not select an ADA reserve:
    // ledger minimum ADA and controller genesis checks apply independently.
    expect
      config_output.value == assets.add(
        assets.from_lovelace(assets.lovelace_of(config_output.value)),
        controller,
        // ID is the permanent token authenticating this immutable Config.
        types.id_name,
        1,
      )

    // Resolve the proposed initial vault State output and its inline datum.
    expect Some(state_output) = list.at(tx.outputs, registration.state_output)
    expect InlineDatum(state_raw) = state_output.datum
    // Decode the real CTVS State wire shape and recursively typed fields.
    let state = decode.state(state_raw)
    // The certificate commits to the ENTIRE extended Config datum, including its
    // Terms, pool binding and other fields. This is distinct from instance_hash.
    let config_hash = blake2b_256(builtin.serialise_data(config_raw))
    // Select the fields this factory checks. The ignored fields still belong to
    // the real State schema; complete State validity is checked by the controller.
    expect  
        State {
          vault_policy: state_policy,
          backing_assets,
          economic_supply,
          ..
        }
      = state
    // A newly registered vault belongs to this controller and starts with no
    // principal backing or economic share supply. The controller's genesis also
    // checks initial sequence, fees, pause flags, rewards and storage accounting.
    expect
      state_policy == controller && backing_assets == 0 && economic_supply == 0
    // Unlike immutable Config, State lives at the vault controller's own address
    // so its future transitions must execute that controller's spending handler.
    expect state_output.address == from_script(controller)
    // Keep the State output free of an attached reference script.
    expect state_output.reference_script == None
    // Initial State holds only ADA and ONE controller.STATE token. No underlying,
    // reward or share token can be hidden in this initial output.
    expect
      state_output.value == assets.add(
        assets.from_lovelace(assets.lovelace_of(state_output.value)),
        controller,
        // STATE authenticates the vault's single evolving accounting UTxO.
        types.state_name,
        1,
      )

    // Resolve the third proposed output: the immutable registration certificate.
    expect Some(proof_output) = list.at(
      tx.outputs,
      registration.registration_output,
    )
    // The certificate must contain inline Registration data.
    expect InlineDatum(proof_raw) = proof_output.datum
    expect proof: Registration = proof_raw
    // Require exact equality with the certificate this factory is willing to
    // issue. The caller cannot substitute any identity, label or commitment.
    expect
      proof == Registration {
        // Registration datum format version.
        version: 1,
        // The approved, instance-specific vault controller script hash.
        controller,
        // The same controller program also mints the permanent State identity.
        state_policy: controller,
        // Bind the precise token name; policy equality alone is insufficient.
        state_name: types.state_name,
        // ASCII "CTVS1-MIXED-FACTORY-1": the supported implementation label.
        implementation: #"43545653312d4d495845442d464143544f52592d31",
        // Commitment to version + seed + settings hash for this controller.
        instance_hash,
        // Commitment to the exact Config datum stored in config_output.
        config_hash,
      }
    // Lock the certificate permanently, alongside Config at the same lock script.
    expect proof_output.address == from_script(config_lock)
    // The certificate output must carry no reference script.
    expect proof_output.reference_script == None
    // Require only ADA plus ONE certificate NFT. Its policy is THIS factory's
    // policy; its asset name is the 28-byte controller hash. Copying the datum
    // cannot reproduce a token under the trusted factory policy.
    expect
      proof_output.value == assets.add(
        assets.from_lovelace(assets.lovelace_of(proof_output.value)),
        // Certificate issuer: this factory's policy ID.
        policy,
        // Certificate asset name: the controller it recognizes.
        controller,
        1,
      )

    // Constrain the ENTIRE transaction's mint value, across all policies:
    //   controller.ID = +1, controller.STATE = +1, factory.controller = +1.
    // No shares, extra certificates, unrelated mints or burns are permitted here.
    // Minting under controller also forces its independent mint handler to run;
    // this factory's partial State checks cannot bypass controller genesis.
    expect
      tx.mint == assets.add(
        assets.add(
          // Start with the Config identity token under the vault policy.
          assets.from_asset(controller, types.id_name, 1),
          // Add the State identity token under that same vault policy.
          controller,
          types.state_name,
          1,
        ),
        // Add the registration NFT under this factory policy, named by controller.
        policy,
        controller,
        1,
      )
    // Config, State and certificate must occupy three different output indices.
    // A single output cannot satisfy multiple creation roles.
    expect
      registration.config_output != registration.state_output && registration.config_output != registration.registration_output && registration.state_output != registration.registration_output
    // Every expect above succeeded: authorize this factory's certificate mint.
    True
  }

  // Reject every non-mint purpose, including spending at this script hash.
  // Certificate burns also fail the exact positive-mint requirement above.
  else(_) {
    fail
  }
}
