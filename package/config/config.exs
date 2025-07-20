import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:mfa]

# Configure specific modules' log levels - only show errors
config :logger,
  compile_time_purge_matching: [
    # Swarm modules - only show errors
    [module: Swarm.Distribution.Ring, level_lower_than: :error],
    [module: Swarm.Distribution.Strategy, level_lower_than: :error],
    [module: Swarm.Registry, level_lower_than: :error],
    [module: Swarm.Tracker, level_lower_than: :error],
    [module: Swarm.Distribution.StaticQuorumRing, level_lower_than: :error],
    [module: Swarm.Distribution.Handler, level_lower_than: :error],
    [module: Swarm.IntervalTreeClock, level_lower_than: :error],
    [module: Swarm.Logger, level_lower_than: :error],
    [module: Swarm, level_lower_than: :error]
  ]

import_config "#{Mix.env()}.exs"
