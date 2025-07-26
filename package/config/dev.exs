import Config

alias ExESDB.EnVars, as: EnVars

# Reduce Ra and Khepri verbosity - only show warnings and errors
config :khepri,
  log_level: :warning,
  logger: true

config :ra,
  log_level: :warning,
  logger: true

config :logger, :console,
  format: "$time ($metadata) [$level] $message\n",
  metadata: [:mfa],
  level: :info,
  # Multiple filters to reduce noise from various components
  filters: [
    ra_noise: {ExESDB.LoggerFilters, :filter_ra},
    khepri_noise: {ExESDB.LoggerFilters, :filter_khepri},
    swarm_noise: {ExESDB.LoggerFilters, :filter_swarm},
    libcluster_noise: {ExESDB.LoggerFilters, :filter_libcluster}
  ]

# LibCluster configuration moved to runtime.exs for dynamic configuration

config :ex_esdb, :logger, level: :debug

config :ex_esdb, :ex_esdb,
  data_dir: "tmp/reg_gh",
  store_id: :reg_gh,
  timeout: 10_000,
  # Changed from :single to :cluster
  db_type: :cluster

# Reduce Swarm logging noise - only show true errors
config :swarm,
  log_level: :error,
  logger: true

# Runtime filtering for any remaining Swarm noise
config :logger,
  level: :info,
  # Additional filters for runtime messages
  backends: [:console],
  handle_otp_reports: true,
  handle_sasl_reports: false

config :ex_esdb_gater, :logger, level: :debug
