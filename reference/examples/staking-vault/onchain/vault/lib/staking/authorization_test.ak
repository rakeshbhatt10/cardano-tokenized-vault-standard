// Generated shared golden vectors; do not edit by hand.

use aiken/builtin
use staking/authorization

test first_deposit() {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d8799f01581c1111111111111111111111111111111111111111111111111111111158202222222222222222222222222222222222222222222222222222222222222222d879801864d8799fd8799f5820444444444444444444444444444444444444444444444444444444444444444400ffff00d8799f444354565302d8799fd8799fd8799fd8799f581c33333333333333333333333333333333333333333333333333333333ffd87a80ffd87a80ff1865010001ffff0a00ff"
  expect
    builtin.serialise_data(
      authorization.staking_action(authorization.decode(raw)),
    ) == #"d8799f186458202222222222222222222222222222222222222222222222222222222222222222d8799fd8799f5820444444444444444444444444444444444444444444444444444444444444444400ffffff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test topup_deposit() {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(1, []),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d8799f01581c1111111111111111111111111111111111111111111111111111111158202222222222222222222222222222222222222222222222222222222222222222d879801864d87a8000d8799f444354565302d8799fd8799fd8799fd8799f581c33333333333333333333333333333333333333333333333333333333ffd87a80ffd87a80ff1865010001ffff0a00ff"
  expect
    builtin.serialise_data(
      authorization.staking_action(authorization.decode(raw)),
    ) == #"d8799f186458202222222222222222222222222222222222222222222222222222222222222222d87a80ff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test topup_mint() {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(1, []),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            1,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d8799f01581c1111111111111111111111111111111111111111111111111111111158202222222222222222222222222222222222222222222222222222222222222222d879801864d87a8000d8799f444354565302d87a9fd8799fd8799fd8799f581c33333333333333333333333333333333333333333333333333333333ffd87a80ffd87a80ff1865010001ffff0a00ff"
  expect
    builtin.serialise_data(
      authorization.staking_action(authorization.decode(raw)),
    ) == #"d8799f186458202222222222222222222222222222222222222222222222222222222222222222d87a80ff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test withdraw() {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(1, []),
      builtin.i_data(100),
      builtin.constr_data(1, []),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            2,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.i_data(1),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d8799f01581c1111111111111111111111111111111111111111111111111111111158202222222222222222222222222222222222222222222222222222222222222222d87a801864d87a8000d8799f444354565302d87b9fd8799fd8799fd8799f581c33333333333333333333333333333333333333333333333333333333ffd87a80ffd87a80ff1865010001ffff0001ff"
  expect
    builtin.serialise_data(
      authorization.staking_action(authorization.decode(raw)),
    ) == #"d905039f186458202222222222222222222222222222222222222222222222222222222222222222ff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test redeem() {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(1, []),
      builtin.i_data(100),
      builtin.constr_data(1, []),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            3,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.i_data(1),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d8799f01581c1111111111111111111111111111111111111111111111111111111158202222222222222222222222222222222222222222222222222222222222222222d87a801864d87a8000d8799f444354565302d87c9fd8799fd8799fd8799f581c33333333333333333333333333333333333333333333333333333333ffd87a80ffd87a80ff1865010001ffff0001ff"
  expect
    builtin.serialise_data(
      authorization.staking_action(authorization.decode(raw)),
    ) == #"d905039f186458202222222222222222222222222222222222222222222222222222222222222222ff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test collect_fees() {
  let raw = builtin.constr_data(
    1,
    [
      builtin.i_data(1),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(5, [builtin.i_data(0), builtin.i_data(1)]),
        ],
      ),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d87a9f01d8799f444354565302d87e9f0001ffffff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test topup_reserve() {
  let raw = builtin.constr_data(
    1,
    [
      builtin.i_data(1),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(6, [builtin.i_data(10), builtin.i_data(0)]),
        ],
      ),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d87a9f01d8799f444354565302d87f9f0a00ffffff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test set_pause() {
  let raw = builtin.constr_data(
    1,
    [
      builtin.i_data(1),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(7, [builtin.i_data(1), builtin.i_data(0)]),
        ],
      ),
    ],
  )
  expect
    builtin.serialise_data(raw) == #"d87a9f01d8799f444354565302d905009f0100ffffff"
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test legacy_three_field() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test draft_seven_field() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test extra_field() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test unsupported_version() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(2),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test short_pool() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(#"000000000000000000000000000000000000000000000000000000"),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test short_position() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"00000000000000000000000000000000000000000000000000000000000000",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test operation_extra_field() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, [builtin.i_data(1)]),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test zero_amount() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test overflow_amount() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(9223372036854775808),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test invalid_option() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(2, []),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test continuation_mismatch() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(2),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test exit_as_entry() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(1, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(0),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test entry_reward_output() fail {
  let raw = builtin.constr_data(
    0,
    [
      builtin.i_data(1),
      builtin.b_data(
        #"11111111111111111111111111111111111111111111111111111111",
      ),
      builtin.b_data(
        #"2222222222222222222222222222222222222222222222222222222222222222",
      ),
      builtin.constr_data(0, []),
      builtin.i_data(100),
      builtin.constr_data(
        0,
        [
          builtin.constr_data(
            0,
            [
              builtin.b_data(
                #"4444444444444444444444444444444444444444444444444444444444444444",
              ),
              builtin.i_data(0),
            ],
          ),
        ],
      ),
      builtin.i_data(0),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
      builtin.i_data(10),
      builtin.i_data(1),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}

test maintenance_with_user_action() fail {
  let raw = builtin.constr_data(
    1,
    [
      builtin.i_data(1),
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"43545653"),
          builtin.i_data(2),
          builtin.constr_data(
            0,
            [
              builtin.constr_data(
                0,
                [
                  builtin.constr_data(
                    0,
                    [
                      builtin.constr_data(
                        0,
                        [
                          builtin.b_data(
                            #"33333333333333333333333333333333333333333333333333333333",
                          ),
                        ],
                      ),
                      builtin.constr_data(1, []),
                    ],
                  ),
                  builtin.constr_data(1, []),
                ],
              ),
              builtin.i_data(101),
              builtin.i_data(1),
              builtin.i_data(0),
              builtin.i_data(1),
            ],
          ),
        ],
      ),
    ],
  )
  when authorization.decode(raw) is {
    authorization.AuthorizeStaking { version, .. } -> version == 1
    authorization.Maintenance { version, .. } -> version == 1
  }
}
