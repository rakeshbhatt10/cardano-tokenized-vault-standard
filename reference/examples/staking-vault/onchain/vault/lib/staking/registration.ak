// This validates the agreed CTVS profile, NOT the authentic factory NFT policy.
use aiken/builtin
use aiken/collection/list
use aiken/primitive/bytearray

pub const implementation = #"43545653312d4d495845442d464143544f52592d31"

pub type Registration {
  version: Int,
  controller: ByteArray,
  state_policy: ByteArray,
  state_name: ByteArray,
  implementation: ByteArray,
  instance_hash: ByteArray,
  config_hash: ByteArray,
}

pub fn decode(raw: Data) -> Registration {
  let Pair(tag, fields) = builtin.un_constr_data(raw)
  expect tag == 0 && list.length(fields) == 7
  expect proof: Registration = raw
  expect
    proof.version == 1 && bytearray.length(proof.controller) == 28 && proof.state_policy == proof.controller
  expect
    proof.state_name == #"5354415445" && proof.implementation == implementation
  expect
    bytearray.length(proof.instance_hash) == 32 && bytearray.length(
      proof.config_hash,
    ) == 32
  proof
}
