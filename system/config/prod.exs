import Config

config :khepri,
  log_level: :information,
  logger: true

config :ra,
  log_level: :information,
  logger: true

config :logger, :console,
  format: "$time ($metadata) [$level] $message\n",
  metadata: [:mfa],
  level: :debug

config :ex_esdb,
  logger: true,
  log_level: :debug

config :ex_esdb, :khepri,
  data_dir: "/data",
  store_id: :reg_gh,
  timeout: 2_000,
  db_type: :cluster,
  seed_nodes: [],
  pub_sub: :ex_esdb_pubsub
