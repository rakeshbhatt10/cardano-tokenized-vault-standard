use staking/authorization
use staking/registration.{Registration}

fn proof() -> Registration {
  Registration {
    version: 1,
    controller: #"11111111111111111111111111111111111111111111111111111111",
    state_policy: #"11111111111111111111111111111111111111111111111111111111",
    state_name: #"5354415445",
    implementation: registration.implementation,
    instance_hash: #"2222222222222222222222222222222222222222222222222222222222222222",
    config_hash: #"3333333333333333333333333333333333333333333333333333333333333333",
  }
}

test supported_profile() {
  let raw: Data = proof()
  let decoded = registration.decode(raw)
  decoded.version == 1
}

test identity_probe_is_not_admission() fail {
  let raw: Data = Registration {
    ..proof(),
    implementation: #"464143544f52592d4944454e544954592d50524f42452d31",
  }
  let decoded = registration.decode(raw)
  decoded.version == 1
}

test substituted_state_policy() fail {
  let raw: Data = Registration {
    ..proof(),
    state_policy: #"22222222222222222222222222222222222222222222222222222222",
  }
  let decoded = registration.decode(raw)
  decoded.version == 1
}

test unsupported_registration_version() fail {
  let raw: Data = Registration { ..proof(), version: 2 }
  let decoded = registration.decode(raw)
  decoded.version == 1
}

test vault_pool_requires_factory_anchor() {
  !authorization.valid_factory_policy(True, None)
}

test wallet_pool_has_no_factory_anchor() {
  authorization.valid_factory_policy(False, None)
}
