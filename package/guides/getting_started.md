# Getting Started with ExESDB

## Introduction

Event Sourcing with CQRS is a technique for building applications that are based on an immutable log of events, which makes it ideal for building concurrent, distributed systems.

Though it is gaining popularity, the number of options for storing these events is limited and require specialized services like Kurrent (aka Greg's EventStore) or AxonIQ.

One of the strong-points of the BEAM is, that it comes 'batteries included': there are BEAM-native libraries for many common tasks, like: storage, pub/sub, caching, logging, telemetry, etc.

`ExESDB` is an attempt to create a BEAM-native Event Store written in Erlang/Elixir, building further upon the [Khepri](https://github.com/rabbitmq/khepri) library, which in turn builds upon the [Ra](https://github.com/rabbitmq/ra) library.

## Status

**This is a work in progress**

The project is in an early stage of development, and is not ready for production use.

Source code is available on [GitHub](https://github.com/beam-campus/ex-esdb).

## Installation

In your `mix.exs` file:

```elixir
def deps do
  [
    {:ex_esdb, "~> 0.0.16"}
  ]
end
```

## Configuration

> **Note**: For detailed configuration examples including umbrella applications, see the [Configuring ExESDB Applications](configuring-exesdb-apps.md) guide.

1. in your `config/config.exs` file:

```elixir
# Example standalone configuration
# If your app is named :my_event_store
config :my_event_store, :ex_esdb,
  data_dir: "/var/lib/ex_esdb",
  store_id: :my_store,
  timeout: 5000,
  db_type: :cluster,
  pub_sub: :my_pubsub,
  reader_idle_ms: 15000,
  writer_idle_ms: 12000,
  store_description: "My Event Store",
  store_tags: ["production", "events"]

# Configure libcluster (recommended)
config :libcluster,
  topologies: [
    example: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1,
        secret: "my_secret"
      ]
    ]
  ]
```

2. from the ENVIRONMENT:

```bash

EX_ESDB_DATA_DIR="/var/lib/ex_esdb"
EX_ESDB_STORE_ID=my_store
EX_ESDB_DB_TYPE=cluster
EX_ESDB_TIMEOUT=5000
EX_ESDB_PUB_SUB=my_pubsub

```

## Usage

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
opts = ExESDB.Options.app_env(:my_event_store)
    children = [
      {ExESDB.System, opts},
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
```
