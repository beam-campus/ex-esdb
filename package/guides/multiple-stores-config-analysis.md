# Multiple Stores in ExESDB Cluster - Configuration Analysis

## Current State Analysis

Currently, ExESDB operates with a single Khepri store per cluster, configured through:

1. **Configuration sources** (in priority order):
   - Environment variables (e.g., `EX_ESDB_STORE_ID`)
   - Application configuration (`:ex_esdb, :khepri`)
   - Default values

2. **Key configuration parameters**:
   - `store_id`: Unique identifier for the store (atom)
   - `data_dir`: Directory for data storage  
   - `timeout`: Operation timeout
   - `db_type`: `:single` or `:cluster`
   - `pub_sub`: PubSub mechanism

3. **Current architecture**:
   - One `ExESDB.Store` GenServer per node
   - One Khepri store instance per cluster
   - All nodes must have the same `store_id` to join the cluster

## Proposal: Multiple Stores via Configuration

### Option 1: Multi-Store Configuration Array

#### Configuration Format
```elixir
config :ex_esdb, :khepri,
  # Keep existing single store config for backward compatibility
  data_dir: "/data",
  store_id: :primary_store,
  timeout: 10_000,
  db_type: :cluster,
  pub_sub: :ex_esdb_pubsub,
  # New: Additional stores configuration
  additional_stores: [
    %{
      store_id: :events_store,
      data_dir: "/data/events",
      timeout: 15_000
    },
    %{
      store_id: :snapshots_store,
      data_dir: "/data/snapshots", 
      timeout: 5_000
    }
  ]
```

#### Implementation Changes Required

1. **Transform ExESDB.Store to Supervisor**:
```elixir
defmodule ExESDB.Store do
  use Supervisor
  
  def init(opts) do
    primary_store = build_store_child_spec(opts)
    additional_stores = build_additional_stores(opts)
    
    children = [primary_store | additional_stores]
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp build_additional_stores(opts) do
    opts
    |> Keyword.get(:additional_stores, [])
    |> Enum.map(&build_store_child_spec/1)
  end
end
```

2. **Create StoreWorker GenServer**:
```elixir
defmodule ExESDB.StoreWorker do
  use GenServer
  
  def start_link(opts) do
    store_id = Keyword.fetch!(opts, :store_id)
    GenServer.start_link(__MODULE__, opts, name: store_id)
  end
  
  def init(opts) do
    # Same logic as current Store.init/1
    case start_khepri(opts) do
      {:ok, store} -> {:ok, [config: opts, store: store]}
      reason -> {:error, [config: opts, store: nil]}
    end
  end
end
```

### Option 2: Multi-Store Via Environment Variables

#### Configuration Format
```bash
# Primary store (backward compatible)
export EX_ESDB_STORE_ID=primary_store
export EX_ESDB_DATA_DIR=/data

# Additional stores
export EX_ESDB_ADDITIONAL_STORES="events_store:/data/events,snapshots_store:/data/snapshots"
export EX_ESDB_STORE_TIMEOUTS="events_store:15000,snapshots_store:5000"
```

#### Parsing Logic
```elixir
defmodule ExESDB.MultiStoreConfig do
  def parse_additional_stores do
    case System.get_env("EX_ESDB_ADDITIONAL_STORES") do
      nil -> []
      stores_str -> 
        stores_str
        |> String.split(",")
        |> Enum.map(&parse_store_config/1)
    end
  end
  
  defp parse_store_config(store_str) do
    [store_id, data_dir] = String.split(store_str, ":")
    %{
      store_id: String.to_atom(store_id),
      data_dir: data_dir,
      timeout: get_store_timeout(store_id)
    }
  end
end
```

## What Happens with Different Node Configurations?

### Scenario 1: Store ID Mismatch

**Node A Config:**
```elixir
config :ex_esdb, :khepri, store_id: :store_a
```

**Node B Config:**
```elixir
config :ex_esdb, :khepri, store_id: :store_b
```

**Result:**
- Nodes will form separate, isolated Khepri clusters
- Each node will be the leader of its own cluster
- No data synchronization between nodes
- Effectively creates multiple single-node clusters

### Scenario 2: Partial Store Overlap

**Node A Config:**
```elixir
config :ex_esdb, :khepri,
  store_id: :primary_store,
  additional_stores: [
    %{store_id: :events_store},
    %{store_id: :snapshots_store}
  ]
```

**Node B Config:**
```elixir
config :ex_esdb, :khepri,
  store_id: :primary_store,
  additional_stores: [
    %{store_id: :events_store}
    # Missing snapshots_store
  ]
```

**Result:**
- `primary_store` and `events_store` form proper clusters
- `snapshots_store` only exists on Node A (single-node cluster)
- Applications expecting `snapshots_store` on Node B will fail
- Potential data inconsistency issues

### Scenario 3: Different Data Directories

**Node A Config:**
```elixir
config :ex_esdb, :khepri,
  store_id: :primary_store,
  data_dir: "/data/node_a"
```

**Node B Config:**
```elixir
config :ex_esdb, :khepri,
  store_id: :primary_store,
  data_dir: "/data/node_b"
```

**Result:**
- Nodes can successfully join the same Khepri cluster
- Each node maintains its own local data directory
- Data is replicated between nodes as per Khepri's clustering
- This is the expected and correct behavior

### Scenario 4: Timeout Mismatches

**Node A Config:**
```elixir
config :ex_esdb, :khepri,
  store_id: :primary_store,
  timeout: 5_000
```

**Node B Config:**
```elixir
config :ex_esdb, :khepri,
  store_id: :primary_store,
  timeout: 15_000
```

**Result:**
- Nodes join the same cluster successfully
- Node A may timeout on operations that Node B handles fine
- Potential for inconsistent behavior during high-load scenarios
- Operations may fail differently on each node

## Risks and Considerations

### 1. **Configuration Drift**
- **Risk**: Nodes in the same cluster having different store configurations
- **Impact**: Split clusters, data inconsistency, operational failures
- **Mitigation**: 
  - Configuration validation during startup
  - Health checks to detect configuration mismatches
  - Centralized configuration management

### 2. **Split Brain Scenarios**
- **Risk**: Nodes with different store IDs thinking they're in the same cluster
- **Impact**: Data divergence, conflicts during cluster healing
- **Mitigation**:
  - Strict validation of store IDs before joining
  - Cluster membership verification
  - Consistent cluster discovery mechanisms

### 3. **Operational Complexity**
- **Risk**: Multiple stores increase monitoring, backup, and maintenance complexity
- **Impact**: Higher operational overhead, potential for human error
- **Mitigation**:
  - Standardized tooling for multi-store operations
  - Automated backup and monitoring for all stores
  - Clear operational procedures

### 4. **Resource Contention**
- **Risk**: Multiple Khepri stores competing for system resources
- **Impact**: Performance degradation, potential instability
- **Mitigation**:
  - Resource limits per store
  - Monitoring of resource usage
  - Careful capacity planning

## Recommended Implementation Strategy

### Phase 1: Foundation (Recommended)
1. **Implement configuration validation**:
   - Verify store consistency across cluster nodes
   - Add startup checks for configuration drift
   - Implement health endpoints for configuration monitoring

2. **Create store registry**:
   - Central registry of all configured stores
   - API to query available stores
   - Validation of store existence before operations

### Phase 2: Multi-Store Support
1. **Transform Store to Supervisor**:
   - Convert existing singleton to supervisor pattern
   - Maintain backward compatibility
   - Add support for additional stores

2. **Update dependent modules**:
   - Modify Streams, Snapshots, etc. to accept store_id parameter
   - Update APIs to support multi-store operations
   - Ensure routing to correct store instances

### Phase 3: Advanced Features
1. **Cross-store operations**:
   - Transactions spanning multiple stores
   - Cross-store queries and joins
   - Consistent backup/restore across stores

2. **Dynamic store management**:
   - Runtime addition/removal of stores
   - Store migration tools
   - Load balancing across stores

## Configuration Validation Implementation

```elixir
defmodule ExESDB.ConfigValidator do
  def validate_cluster_consistency(local_config) do
    connected_nodes = Node.list()
    
    for node <- connected_nodes do
      case :rpc.call(node, ExESDB.Config, :get_stores_config, [], 5000) do
        {:ok, remote_config} ->
          validate_config_match(local_config, remote_config, node)
        {:error, reason} ->
          {:error, {:rpc_failed, node, reason}}
      end
    end
  end
  
  defp validate_config_match(local, remote, node) do
    local_stores = get_store_ids(local)
    remote_stores = get_store_ids(remote)
    
    case local_stores -- remote_stores do
      [] -> :ok
      missing -> {:error, {:config_mismatch, node, missing}}
    end
  end
end
```

## Conclusion

**Multiple stores via configuration is feasible** but requires careful implementation to avoid configuration drift and split-brain scenarios. The key challenges are:

1. **Configuration consistency** across cluster nodes
2. **Operational complexity** of managing multiple stores
3. **Resource management** and performance implications

**Recommended approach**: Start with configuration validation and health checks, then gradually implement multi-store support with strong consistency guarantees.

The libcluster mechanism should be used for node discovery, avoiding the anti-pattern of seed nodes as per the user's rule.
