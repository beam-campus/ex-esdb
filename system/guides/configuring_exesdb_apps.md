# Configuring ExESDB Applications

This guide explains how to configure ExESDB in both standalone and umbrella applications.

## Configuration Overview

ExESDB supports two deployment patterns:

1. **Standalone Applications**: A single OTP application that uses ExESDB
2. **Umbrella Applications**: Multiple child applications within an umbrella project, each with their own ExESDB configuration

The configuration format is always: `config :your_app_name, :ex_esdb, [options]` where:
- `:your_app_name` is the name of your OTP application
- `:ex_esdb` is the configuration namespace that ExESDB looks for
- `[options]` are the ExESDB configuration options

## Standalone Application Configuration

For a standalone application, configure ExESDB under your application's name:

```elixir
# config/config.exs
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

# Libcluster configuration (recommended over seed_nodes)
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

### Usage in Standalone Apps

```elixir
# Uses the default context (your app name)
ExESDB.Options.data_dir()          # "/var/lib/ex_esdb"
ExESDB.Options.store_id()          # :my_store
ExESDB.Options.db_type()           # :cluster
```

## Umbrella Application Configuration

For umbrella applications, each child application can have its own ExESDB configuration:

```elixir
# config/config.exs (umbrella root)

# Child app 1: orders service
config :orders_service, :ex_esdb,
  data_dir: "/var/lib/orders_events",
  store_id: :orders_store,
  timeout: 5000,
  db_type: :cluster,
  pub_sub: :orders_pubsub,
  reader_idle_ms: 10000,
  writer_idle_ms: 8000,
  store_description: "Orders Event Store",
  store_tags: ["orders", "production"]

# Child app 2: inventory service
config :inventory_service, :ex_esdb,
  data_dir: "/var/lib/inventory_events",
  store_id: :inventory_store,
  timeout: 3000,
  db_type: :single,
  pub_sub: :inventory_pubsub,
  reader_idle_ms: 12000,
  writer_idle_ms: 10000,
  store_description: "Inventory Event Store",
  store_tags: ["inventory", "production"]

# Child app 3: user service
config :user_service, :ex_esdb,
  data_dir: "/var/lib/user_events",
  store_id: :user_store,
  timeout: 4000,
  db_type: :cluster,
  pub_sub: :user_pubsub,
  reader_idle_ms: 8000,
  writer_idle_ms: 6000,
  store_description: "User Event Store",
  store_tags: ["users", "auth", "production"]

# Shared libcluster configuration
config :libcluster,
  topologies: [
    umbrella_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1,
        secret: "umbrella_secret"
      ]
    ]
  ]
```

### Usage in Umbrella Apps

ExESDB provides several ways to work with different contexts in umbrella applications:

#### Setting Context

```elixir
# Set context for orders service
ExESDB.Options.set_context(:orders_service)
ExESDB.Options.data_dir()          # "/var/lib/orders_events"
ExESDB.Options.store_id()          # :orders_store
```

#### Explicit Context

```elixir
# Use with explicit context
ExESDB.Options.data_dir(:inventory_service)     # "/var/lib/inventory_events"
ExESDB.Options.store_id(:user_service)          # :user_store
```

#### Context Wrapper

```elixir
# Use with context wrapper
ExESDB.Options.with_context(:orders_service, fn ->
  ExESDB.Options.db_type()         # :cluster
  ExESDB.Options.timeout()         # 5000
end)
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data_dir` | String | `"/data"` | Directory for storing event data |
| `store_id` | Atom | `:undefined` | Unique identifier for the store |
| `timeout` | Integer | `10_000` | Timeout in milliseconds |
| `db_type` | Atom | `:single` | Database type (`:single` or `:cluster`) |
| `pub_sub` | Atom | `:ex_esdb_pubsub` | PubSub module name |
| `reader_idle_ms` | Integer | `10_000` | Reader idle timeout in milliseconds |
| `writer_idle_ms` | Integer | `10_000` | Writer idle timeout in milliseconds |
| `store_description` | String | `"undefined!"` | Human-readable store description |
| `store_tags` | List | `[]` | List of tags for the store |

## Environment Variable Overrides

All configuration options can be overridden using environment variables, which take precedence over application configuration:

```bash
# These will override any app configuration
export EX_ESDB_DATA_DIR="/tmp/events"
export EX_ESDB_STORE_ID="temp_store"
export EX_ESDB_DB_TYPE="single"
export EX_ESDB_TIMEOUT="2000"
export EX_ESDB_PUB_SUB="temp_pubsub"
export EX_ESDB_READER_IDLE_MS="5000"
export EX_ESDB_WRITER_IDLE_MS="4000"
export EX_ESDB_STORE_DESCRIPTION="Temporary Store"
export EX_ESDB_STORE_TAGS="temp,testing"
```

Environment variables are especially useful for:
- Development vs production configurations
- Container deployments
- Testing scenarios
- Runtime configuration changes

## Clustering Configuration

ExESDB is designed to work with `libcluster` for node discovery and clustering. The old `seed_nodes` mechanism has been deprecated in favor of `libcluster`'s more robust topology strategies.

### Libcluster Strategies

Common strategies include:

- **Gossip**: For local network discovery
- **Kubernetes**: For Kubernetes deployments
- **ECS**: For AWS ECS deployments
- **EpMD**: For Erlang Port Mapper Daemon
- **DNS**: For DNS-based discovery

Refer to the [libcluster documentation](https://hexdocs.pm/libcluster/) for detailed configuration options.

## Best Practices

1. **Use libcluster**: Always prefer `libcluster` over manual seed nodes configuration
2. **Isolate configurations**: In umbrella apps, keep each service's configuration separate
3. **Environment-specific configs**: Use environment variables for deployment-specific settings
4. **Meaningful names**: Use descriptive `store_id` and `store_description` values
5. **Tagging**: Use `store_tags` for operational visibility and monitoring
6. **Resource sizing**: Adjust timeout and idle settings based on your workload characteristics

## Migration from Legacy Configuration

If you're migrating from the legacy `khepri` configuration format, update your configuration from:

```elixir
# Old format (deprecated)
config :ex_esdb, :khepri, [options]
```

To:

```elixir
# New format
config :your_app_name, :ex_esdb, [options]
```

The new format provides better isolation and supports umbrella applications more effectively.
