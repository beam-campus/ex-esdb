# How ExESDB Handles Multiple Stores

This document describes the dynamic store creation and management capabilities added to ExESDB, allowing users to create multiple event stores on-demand within a single cluster.

## Overview

Previously, ExESDB was configured with a single store ID at startup. Now, with the `ExESDB.StoreManager`, users can:

- Create new stores dynamically at runtime
- Remove stores when no longer needed
- List and query store status and configuration
- Use multiple stores simultaneously in the same cluster

## Architecture

### Components

1. **ExESDB.StoreManager**: The core GenServer that manages multiple Khepri stores
2. **ExESDBGater.API**: Updated API with store management functions
3. **ExESDB.GatewayWorker**: Updated to handle store management operations

### How It Works

1. The `StoreManager` replaces the single `Store` process in the supervision tree
2. Each store gets its own unique data directory under the base data directory
3. Stores are managed independently but share the same cluster infrastructure
4. All existing stream, subscription, and snapshot operations work with any managed store

## API Reference

### Creating a Store

```elixir
# Fire-and-forget operation
:ok = ExESDBGater.API.create_store(:my_new_store, [timeout: 15_000])
```

### Removing a Store

```elixir
# Fire-and-forget operation
:ok = ExESDBGater.API.remove_store(:my_store)
```

### Listing Stores

```elixir
{:ok, stores} = ExESDBGater.API.list_stores()
# Returns: %{store_id => %{status: :running, config: [...]}}
```

### Getting Store Status

```elixir
{:ok, :running} = ExESDBGater.API.get_store_status(:my_store)
```

### Getting Store Configuration

```elixir
{:ok, config} = ExESDBGater.API.get_store_config(:my_store)
```

## Store Operations

Once a store is created, you can use it with all existing operations:

```elixir
# Append events to a specific store
{:ok, version} = ExESDBGater.API.append_events(:my_store, "stream-1", events)

# Read events from a specific store
{:ok, events} = ExESDBGater.API.get_events(:my_store, "stream-1", 0, 10)

# List streams in a specific store
{:ok, streams} = ExESDBGater.API.get_streams(:my_store)

# Create subscriptions for a specific store
:ok = ExESDBGater.API.save_subscription(:my_store, :by_stream, "$all", "my_sub")
```

## Configuration

### Default Store

The system still creates a default store on startup using the existing configuration:

```elixir
# In runtime.exs
config :ex_esdb, :khepri,
  data_dir: data_dir(),
  store_id: store_id(),  # This becomes the default store
  timeout: timeout(),
  db_type: db_type(),
  pub_sub: pub_sub()
```

### Dynamic Store Configuration

New stores inherit the default configuration but can override specific settings:

```elixir
ExESDBGater.API.create_store(:custom_store, [
  timeout: 20_000,        # Custom timeout
  # data_dir is automatically set to base_dir/custom_store
])
```

## Data Storage

Each store gets its own data directory:

```
/data/
├── ex_esdb_store/          # Default store
├── user_data_store/        # Custom store 1
├── analytics_store/        # Custom store 2
└── audit_logs_store/       # Custom store 3
```

## Use Cases

### Multi-Tenant Applications

Create separate stores for each tenant:

```elixir
# Create tenant-specific stores
ExESDBGater.API.create_store(:tenant_123_store)
ExESDBGater.API.create_store(:tenant_456_store)

# Use tenant-specific store for operations
ExESDBGater.API.append_events(:tenant_123_store, "orders", events)
```

### Domain Separation

Create stores for different business domains:

```elixir
# Separate stores by domain
ExESDBGater.API.create_store(:user_management_store)
ExESDBGater.API.create_store(:order_processing_store)
ExESDBGater.API.create_store(:analytics_store)
```

### Environment-Specific Stores

Create stores for different purposes:

```elixir
# Development/testing stores
ExESDBGater.API.create_store(:test_store)
ExESDBGater.API.create_store(:staging_store)
```

## Cluster Behavior

- Stores are created on the node that receives the request
- Khepri handles replication across the cluster automatically
- Each store maintains its own Raft consensus group
- Store operations are distributed across cluster nodes via Swarm

## Backward Compatibility

The changes are fully backward compatible:

- Existing single-store configurations continue to work
- All existing APIs work with the default store
- No migration is required for existing deployments

## Best Practices

### Store Naming

Use descriptive, unique atom names:

```elixir
# Good
:user_events_store
:order_processing_store
:analytics_events_store

# Avoid
:store1
:store
:temp
```

### Resource Management

- Monitor store count to avoid resource exhaustion
- Remove unused stores to free up resources
- Consider store lifecycle in your application design

### Configuration

- Use consistent timeout values for related stores
- Plan data directory structure for backup/restore operations
- Consider store-specific configuration needs

## Monitoring

To monitor store health:

```elixir
# Get all stores and their status
{:ok, stores} = ExESDBGater.API.list_stores()

for {store_id, info} <- stores do
  IO.puts("Store #{store_id}: #{info.status}")
end
```

## Error Handling

Common error scenarios:

```elixir
# Store already exists
{:error, :already_exists} = ExESDBGater.API.create_store(:existing_store)

# Store not found
{:error, :not_found} = ExESDBGater.API.get_store_status(:nonexistent_store)
{:error, :not_found} = ExESDBGater.API.remove_store(:nonexistent_store)
```

## Migration Guide

If you're currently using a single store and want to adopt multiple stores:

1. **No immediate action required** - your existing setup continues to work
2. **Gradual migration** - start creating new stores for new features
3. **Optional consolidation** - consider reorganizing existing data into domain-specific stores

## Performance Considerations

- Each store has its own Khepri cluster member
- Memory usage scales with the number of stores
- Network traffic increases with store count due to more Raft groups
- Consider store count limits based on cluster capacity

## Security Considerations

- Store creation/removal should be restricted to authorized operations
- Consider implementing store-level access controls in your application
- Monitor store creation for unauthorized usage

## Limitations

- Store IDs must be valid Elixir atoms
- Each store requires cluster resources (memory, network)
- Maximum practical store count depends on cluster capacity
- Store removal is immediate and irreversible

## Future Enhancements

Potential future improvements:

- Store templates for consistent configuration
- Store migration utilities
- Store-level metrics and monitoring
- Automatic store cleanup policies
- Store backup/restore functionality
