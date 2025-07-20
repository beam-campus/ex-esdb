import Config

alias ExESDB.EnVars, as: EnVars
import ExESDB.Options

config :logger, :console,
  format: "$time [$level] $message\n",
  metadata: [:mfa],
  level: :info,
  # Multiple filters to reduce noise from various components
  filters: [
    ra_noise: {ExESDB.LoggerFilters, :filter_ra},
    khepri_noise: {ExESDB.LoggerFilters, :filter_khepri},
    swarm_noise: {ExESDB.LoggerFilters, :filter_swarm},
    libcluster_noise: {ExESDB.LoggerFilters, :filter_libcluster}
  ]

config :ex_esdb, :ex_esdb,
  data_dir: data_dir(),
  store_id: store_id(),
  timeout: timeout(),
  db_type: db_type(),
  pub_sub: pub_sub(),
  store_description: store_description(),
  store_tags: store_tags()

# LibCluster configuration now uses SharedClusterConfig for consistency
# This prevents conflicts between ExESDB and ExESDBGater
config :libcluster,
  topologies: ExESDBGater.SharedClusterConfig.topology()
