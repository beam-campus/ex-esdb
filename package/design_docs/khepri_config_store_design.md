# Khepri-Based Configuration Storage Design

## Overview

This document outlines the design for implementing a configuration storage system using Khepri itself to manage ExESDB store configurations. This approach enables dynamic runtime configuration, cluster-wide consistency, and simplified configuration management.

## Current State

ExESDB currently uses:
- Application configuration (`config/runtime.exs`)
- Environment variables
- Static configuration at startup
- Single store per configuration

## Proposed Architecture

### Core Components

1. **ExESDB.ConfigStore** - A dedicated Khepri store for configuration data
2. **ExESDB.StoreManager** - Enhanced to read from ConfigStore
3. **ExESDB.ConfigAPI** - API for managing store configurations
4. **ExESDB.ConfigBootstrap** - Bootstrap process for initial configuration

### Configuration Schema

```elixir
# Stored in Khepri at path: [:stores, :config, store_id]
%{
  store_id: :my_store,
  config: %{
    data_dir: "/data/my_store",
    timeout: 15_000,
    db_type: :cluster,
    pub_sub: :native,
    auto_start: true,
    priority: :normal,
    resource_limits: %{
      max_memory_mb: 1024,
      max_connections: 100
    }
  },
  metadata: %{
    created_at: ~U[2024-01-01 00:00:00Z],
    created_by: "system",
    updated_at: ~U[2024-01-01 00:00:00Z],
    updated_by: "admin",
    version: 1
  },
  status: :active  # :active, :inactive, :pending_deletion
}
```

### Implementation Strategy

#### Phase 1: Configuration Store Setup

1. **Create ConfigStore**:
   ```elixir
   # Early in supervision tree
   {ExESDB.ConfigStore, [
     store_id: :ex_esdb_config,
     data_dir: "/data/config",
     timeout: 5_000
   ]}
   ```

2. **Bootstrap Process**:
   - Start with minimal configuration store
   - Migrate existing configuration to Khepri
   - Set up default store configuration

#### Phase 2: Enhanced StoreManager

```elixir
defmodule ExESDB.StoreManager do
  use GenServer

  # Enhanced to watch for configuration changes
  def init(opts) do
    # Subscribe to configuration changes
    :khepri.subscribe(:ex_esdb_config, [:stores, :config, :*])
    
    # Load initial configurations
    configs = load_all_store_configs()
    
    # Start configured stores
    stores = start_configured_stores(configs)
    
    {:ok, %{stores: stores, configs: configs}}
  end

  def handle_info({:khepri, :config_change, store_id, new_config}, state) do
    # Handle dynamic configuration changes
    case new_config do
      nil -> 
        # Store configuration deleted
        stop_store(store_id)
      config -> 
        # Store configuration updated
        update_store_config(store_id, config)
    end
    
    {:noreply, state}
  end
end
```

#### Phase 3: Configuration API

```elixir
defmodule ExESDB.ConfigAPI do
  @doc "Create or update a store configuration"
  def put_store_config(store_id, config) do
    validated_config = validate_config(config)
    
    config_entry = %{
      store_id: store_id,
      config: validated_config,
      metadata: %{
        created_at: DateTime.utc_now(),
        created_by: current_user(),
        version: get_next_version(store_id)
      },
      status: :active
    }
    
    :khepri.put(:ex_esdb_config, [:stores, :config, store_id], config_entry)
  end
  
  @doc "Get store configuration"
  def get_store_config(store_id) do
    :khepri.get(:ex_esdb_config, [:stores, :config, store_id])
  end
  
  @doc "List all store configurations"
  def list_store_configs() do
    :khepri.get_many(:ex_esdb_config, [:stores, :config, :*])
  end
  
  @doc "Delete store configuration"
  def delete_store_config(store_id) do
    :khepri.delete(:ex_esdb_config, [:stores, :config, store_id])
  end
end
```

## Benefits

### 1. Dynamic Configuration
- Add/remove stores without application restarts
- Update store configurations in real-time
- Configuration changes propagate automatically

### 2. Cluster Consistency
- All nodes have identical store configurations
- Khepri's Raft consensus prevents configuration drift
- Automatic failover of configuration data

### 3. Simplified Management
- Single source of truth for all configurations
- Version tracking and audit trails
- Queryable configuration data

### 4. Operational Excellence
- Configuration can be backed up with regular Khepri snapshots
- Roll back configuration changes
- Monitor configuration changes through Khepri's subscription system

## Addressing the Khepri Membership Concern

### The "All Stores on All Nodes" Approach

**Recommendation**: This is a defensible and practical approach for several reasons:

1. **Operational Simplicity**:
   - No complex store placement logic
   - No client routing complexity
   - Uniform cluster behavior

2. **High Availability**:
   - Every store is automatically HA
   - No single points of failure
   - Simple disaster recovery

3. **Khepri's Design**:
   - Built for multiple embedded instances
   - Efficient resource sharing
   - Mature multi-instance support

### Resource Management Strategies

```elixir
# Configuration-based resource management
config = %{
  auto_start: false,  # Only start when first accessed
  priority: :low,     # Resource allocation priority
  resource_limits: %{
    max_memory_mb: 256,
    max_connections: 50
  }
}

# Lazy loading implementation
defmodule ExESDB.StoreManager do
  def get_store(store_id) do
    case Map.get(@stores, store_id) do
      nil -> 
        # Lazy load the store
        start_store_on_demand(store_id)
      store -> 
        store
    end
  end
end
```

## Migration Strategy

### Phase 1: Parallel Configuration
- Keep existing configuration system
- Add Khepri configuration alongside
- Gradual migration of stores

### Phase 2: Hybrid Mode
- New stores use Khepri configuration
- Existing stores continue with old configuration
- Provide migration utilities

### Phase 3: Full Migration
- All stores managed through Khepri
- Remove old configuration system
- Cleanup and optimization

## Implementation Priorities

1. **Core Infrastructure** (Week 1-2)
   - ConfigStore setup
   - Basic configuration schema
   - Bootstrap process

2. **Enhanced StoreManager** (Week 3-4)
   - Dynamic configuration loading
   - Configuration change handling
   - Store lifecycle management

3. **Configuration API** (Week 5-6)
   - CRUD operations for configurations
   - Validation and error handling
   - Version management

4. **Migration Tools** (Week 7-8)
   - Configuration migration utilities
   - Testing and validation
   - Documentation

## Risks and Mitigations

### Risk 1: Configuration Store Failure
- **Mitigation**: Separate configuration store from data stores
- **Fallback**: Local configuration cache with manual recovery

### Risk 2: Configuration Complexity
- **Mitigation**: Start with simple schema, expand gradually
- **Validation**: Comprehensive configuration validation

### Risk 3: Performance Impact
- **Mitigation**: Lazy loading, resource limits, monitoring
- **Optimization**: Store prioritization, selective activation

## Conclusion

The Khepri-based configuration storage approach provides significant benefits:
- Dynamic runtime configuration
- Cluster-wide consistency
- Simplified management
- Operational excellence

The "all stores on all nodes" approach is defensible and aligns with Khepri's design philosophy. With proper resource management and lazy loading, this can be both practical and efficient.

The migration can be done incrementally, allowing for validation and optimization at each step.
