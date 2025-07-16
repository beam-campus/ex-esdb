import Config

config :ex_unit,
  capture_log: false,
  assert_receive_timeout: 5_000,
  refute_receive_timeout: 1_000,
  exclude: [:skip],
  logger: true

config :ex_esdb, :ex_esdb,
  data_dir: "tmp/ex_esdb_store",
  store_id: :ex_test_store,
  timeout: 1_000,
  db_type: :single,
  pub_sub: :ex_esdb_pub_sub
