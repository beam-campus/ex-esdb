# Multiple Stores Implementation Summary

## Multi-Store Operation Overview

Multi-store operation in ExESDB enables running multiple independent event stores within a single cluster instance. This capability allows for:

- **Logical Separation**: Different stores can represent different domains, tenants, or environments
- **Dynamic Management**: Stores can be created and removed on-demand during runtime
- **Independent Operation**: Each store maintains its own event streams, subscriptions, and data storage
- **Cluster Efficiency**: All stores share the same cluster infrastructure while maintaining data isolation

Each store operates as a separate Khepri-backed event store with its own:
- Data directory for persistent storage
- Configuration settings (inheriting from defaults)
- Event streams and subscription management
- Raft consensus logs and snapshots

This design provides a scalable foundation for multi-tenant applications, domain-driven architectures, and flexible event store management without requiring separate cluster deployments.

## What Was Implemented

We successfully implemented dynamic store creation functionality in ExESDB, allowing users to create multiple event stores on-demand within a single cluster.

## Key Changes Made

### 1. ExESDB.StoreManager (New Module)
- **File**: `lib/ex_esdb/store_manager.ex`
- **Purpose**: Manages multiple Khepri stores dynamically
- **Features**:
  - Create stores with unique identifiers
  - Remove stores when no longer needed
  - List all managed stores with their status
  - Query individual store status and configuration
  - Automatic data directory management per store

### 2. Updated ExESDB.System
- **File**: `lib/ex_esdb/system.ex`
- **Change**: Replaced single `ExESDB.Store` with `ExESDB.StoreManager` in supervision tree
- **Impact**: Now supports multiple stores instead of single store

### 3. Updated ExESDBGater.API
- **File**: `/home/rl/work/github.com/beam-campus/ex-esdb-gater/system/lib/ex_esdb_gater/api.ex`
- **New Functions**:
  - `create_store/2` - Create new store (fire-and-forget via cast)
  - `remove_store/1` - Remove store (fire-and-forget via cast)
  - `list_stores/0` - List all stores (synchronous via call)
  - `get_store_status/1` - Get store status (synchronous via call)
  - `get_store_config/1` - Get store configuration (synchronous via call)

### 4. Updated ExESDB.GatewayWorker
- **File**: `lib/ex_esdb/gateway_worker.ex`
- **New Handlers**:
  - `handle_cast({:create_store, store_id, config}, state)` - Handle store creation
  - `handle_cast({:remove_store, store_id}, state)` - Handle store removal
  - `handle_call(:list_stores, _from, state)` - Handle store listing
  - `handle_call({:get_store_status, store_id}, _from, state)` - Handle status queries
  - `handle_call({:get_store_config, store_id}, _from, state)` - Handle config queries

### 5. Documentation
- **File**: `guides/how_exesdb_handles_multiple_stores.md`
- **Content**: Comprehensive guide explaining architecture, API, use cases, and best practices
- **Integration**: Added to `mix.exs` for Hex documentation publishing

### 6. Test Suite
- **File**: `test/ex_esdb/store_manager_test.exs`
- **Coverage**: Tests for store creation, removal, duplication handling, and listing

### 7. Demo Script
- **File**: `examples/dynamic_stores_demo.exs`
- **Purpose**: Demonstrates practical usage of the dynamic store functionality

## Architecture Overview

```
ExESDB.System
├── ExESDB.StoreManager (replaces ExESDB.Store)
│   ├── :default_store (automatically created from config)
│   ├── :user_store_1 (created dynamically)
│   ├── :analytics_store (created dynamically)
│   └── ... (more stores as needed)
├── ExESDB.ClusterSystem
├── ExESDB.Streams
├── ExESDB.Subscriptions
└── ... (other components)
```

## Data Directory Structure

```
/data/
├── ex_esdb_store/          # Default store
│   ├── raft_logs/
│   └── snapshots/
├── user_data_store/        # Dynamic store 1
│   ├── raft_logs/
│   └── snapshots/
├── analytics_store/        # Dynamic store 2
│   ├── raft_logs/
│   └── snapshots/
└── audit_logs_store/       # Dynamic store 3
    ├── raft_logs/
    └── snapshots/
```

## API Usage Examples

```elixir
# Create stores
:ok = ExESDBGater.API.create_store(:user_data_store, [timeout: 15_000])
:ok = ExESDBGater.API.create_store(:analytics_store, [])

# List stores
{:ok, stores} = ExESDBGater.API.list_stores()
# Returns: %{
#   user_data_store: %{status: :running, config: [...]},
#   analytics_store: %{status: :running, config: [...]}
# }

# Use stores for operations
{:ok, version} = ExESDBGater.API.append_events(:user_data_store, "stream-1", events)
{:ok, events} = ExESDBGater.API.get_events(:analytics_store, "metrics", 0, 10)

# Remove stores
:ok = ExESDBGater.API.remove_store(:analytics_store)
```

## Key Benefits

1. **Multi-Tenancy**: Separate stores per tenant/customer
2. **Domain Separation**: Different stores for different business domains
3. **Scalability**: Distribute stores across cluster nodes
4. **Isolation**: Independent failure domains per store
5. **Flexibility**: Dynamic creation/removal based on demand
6. **Backward Compatibility**: Existing single-store setups continue to work

## Design Decisions

### Fire-and-Forget Operations
- Store creation and removal use `GenServer.cast` for better performance
- Reduces blocking on the caller side
- Operations are logged for monitoring

### Synchronous Queries
- Store listing and status queries use `GenServer.call`
- Ensures consistent responses
- Suitable for monitoring and management operations

### Data Directory Management
- Each store gets its own subdirectory under the base data directory
- Automatic directory creation when stores are created
- Prevents data conflicts between stores

### Configuration Inheritance
- New stores inherit default configuration
- Can override specific settings per store
- Maintains consistency while allowing customization

## Performance Considerations

- Each store creates its own Khepri cluster member
- Memory usage scales with number of stores
- Network traffic increases with store count
- Recommended to monitor store count and resource usage

## Future Enhancements

- Store templates for consistent configuration
- Store backup/restore functionality
- Store-level metrics and monitoring
- Automatic cleanup policies
- Store migration utilities

## Testing

The implementation includes comprehensive tests covering:
- Store creation and removal
- Duplicate handling
- Error scenarios
- Configuration management
- Multi-store operations

## Documentation

Complete documentation is available in the guides and will be published to Hex when the package is released.
