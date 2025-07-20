import Config

# Production: Further reduce Ra and Khepri verbosity - only errors
config :khepri,
  log_level: :error,
  logger: true

config :ra,
  log_level: :error,
  logger: true

config :logger, :console,
  format: "$time ($metadata) [$level] $message\n",
  metadata: [:mfa],
  level: :info,
  # Production filters to minimize noise
  filters: [
    ra_noise: {ExESDB.LoggerFilters, :filter_ra},
    khepri_noise: {ExESDB.LoggerFilters, :filter_khepri},
    swarm_noise: {ExESDB.LoggerFilters, :filter_swarm},
    libcluster_noise: {ExESDB.LoggerFilters, :filter_libcluster}
  ]

config :ex_esdb,
  logger: true,
  log_level: :debug

config :ex_esdb, :ex_esdb,
  data_dir: "/data",
  store_id: :reg_gh,
  timeout: 2_000,
  db_type: :cluster,
  pub_sub: :ex_esdb_pubsub

config :swarm,
  log_level: :error,
  logger: true

config :ex_esdb_gater, :logger, level: :debug

config :ex_esdb_gater, :api, pub_sub: :ex_esdb_pubsub
