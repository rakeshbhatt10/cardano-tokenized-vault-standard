use cardano/transaction.{OutputReference}

pub const id_name = #"4944"

pub const state_name = #"5354415445"

// Instance identity shared by controller creation and automatic registration.
pub type Instance {
  version: Int,
  seed: OutputReference,
  settings_hash: ByteArray,
}

pub type Registration {
  version: Int,
  controller: ByteArray,
  state_policy: ByteArray,
  state_name: ByteArray,
  implementation: ByteArray,
  instance_hash: ByteArray,
  config_hash: ByteArray,
}

pub type Register {
  instance: Instance,
  first_part: OutputReference,
  second_part: OutputReference,
  config_output: Int,
  state_output: Int,
  registration_output: Int,
}
