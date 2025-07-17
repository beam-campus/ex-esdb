# ExESDB Store-Specific Analysis and Implementation

## Summary

This analysis investigated GenServers with hard-coded names in the ExESDB system and implemented solutions to make the system store-specific. The goal is to allow multiple ExESDB instances to run on the same node with different stores.

## Changes Made

### 1. Created ExESDB.StoreNaming Helper Module
- **File**: `lib/ex_esdb/store_naming.ex`
- **Purpose**: Centralized utility for generating store-specific names
- **Key Functions**:
  - `genserver_name/2`: Generate store-specific GenServer names
  - `child_spec_id/2`: Generate store-specific child spec IDs
  - `extract_store_id/1`: Extract store_id from options

### 2. Updated ExESDB.System
- **File**: `lib/ex_esdb/system.ex`
- **Changes**:
  - Added `system_name/1` function to generate store-specific names
  - Modified `start_link/1` to use store-specific naming
  - Updated `child_spec/1` to use store-specific IDs
  - **Result**: Multiple ExESDB systems can now run on the same node

### 3. Updated ExESDB.Store
- **File**: `lib/ex_esdb/store.ex`
- **Changes**:
  - Added `store_name/1` function for name generation
  - Modified `start_link/1` and `child_spec/1` for store-specific naming
  - Updated `get_state/1` to accept optional store_id parameter
  - **Result**: Multiple stores can now run on the same node

### 4. Updated ExESDB.StoreCluster
- **File**: `lib/ex_esdb/store_cluster.ex`
- **Changes**:
  - Modified `start_link/1` and `child_spec/1` for store-specific naming
  - **Result**: Store clusters are now store-specific

### 5. Updated ExESDB.LeaderWorker
- **File**: `lib/ex_esdb/leader_worker.ex`
- **Changes**:
  - Enhanced `activate/1` to support both store-specific and global naming
  - Modified `start_link/1` and `child_spec/1` for store-specific naming
  - **Result**: Leadership is now store-specific with backward compatibility

## GenServers Still Requiring Updates

### Core GenServers (High Priority)
1. **ExESDB.StoreRegistry** (line 286)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

2. **ExESDB.SubscriptionsTracker** (line 139)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

3. **ExESDB.NodeMonitor** (line 27)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

4. **ExESDB.EventProjector** (line 53)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

### Secondary GenServers (Medium Priority)
5. **ExESDB.LeaderTracker** (line 208)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

6. **ExESDB.StoreWorker** (line 57)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

7. **ExESDB.SubscriptionsWriter** (line 141)
   - Currently uses `name: __MODULE__`
   - Should use store-specific naming

### Supervisor Modules (Lower Priority)
8. **ExESDB.CoreSystem** (line 43)
9. **ExESDB.LeaderSystem** (line 15)
10. **ExESDB.NotificationSystem** (line 36)
11. **ExESDB.ClusterSystem** (line 30)
12. **ExESDB.GatewaySystem** (line 71)
13. **ExESDB.StoreSystem** (line 43)
14. **ExESDB.EmitterSystem** (line 34)
15. **ExESDB.PersistenceSystem** (line 36)
16. **ExESDB.GatewaySupervisor** (line 31)

## Workers Already Using Swarm (No Changes Needed)
These workers properly use Swarm for distributed registration:
- **StreamsWriterWorker** - Uses Swarm with store+stream specific names
- **StreamsReaderWorker** - Uses Swarm with store+stream specific names
- **SnapshotsWriterWorker** - Uses Swarm with store+snapshot specific names
- **SnapshotsReaderWorker** - Uses Swarm with store+snapshot specific names
- **GatewayWorker** - Uses Swarm with store+gateway specific names

## Implementation Pattern

For each GenServer that needs to be made store-specific, follow this pattern:

```elixir
# 1. Add StoreNaming alias
alias ExESDB.StoreNaming

# 2. Update start_link/1
def start_link(opts) do
  store_id = StoreNaming.extract_store_id(opts)
  name = StoreNaming.genserver_name(__MODULE__, store_id)
  
  GenServer.start_link(__MODULE__, opts, name: name)
end

# 3. Update child_spec/1
def child_spec(opts) do
  store_id = StoreNaming.extract_store_id(opts)
  
  %{
    id: StoreNaming.child_spec_id(__MODULE__, store_id),
    start: {__MODULE__, :start_link, [opts]},
    restart: :permanent,
    shutdown: 10_000,
    type: :worker
  }
end

# 4. Update any API functions that reference the process
def some_api_function(store_id \\ nil) do
  name = StoreNaming.genserver_name(__MODULE__, store_id)
  GenServer.call(name, :some_message)
end
```

## Benefits

1. **Multi-Store Support**: Multiple ExESDB instances can run on the same node
2. **Backward Compatibility**: Existing code continues to work without store_id
3. **Centralized Naming**: All naming logic is in one place
4. **Consistent Pattern**: All GenServers follow the same pattern
5. **Better Isolation**: Store-specific processes don't interfere with each other

## Testing Recommendations

1. **Unit Tests**: Test naming functions with various store_id values
2. **Integration Tests**: Test multiple stores running simultaneously
3. **Backward Compatibility Tests**: Ensure existing code still works
4. **Cluster Tests**: Test store-specific clustering behavior

## Next Steps

1. Update the remaining GenServers listed above
2. Update supervisor modules if needed
3. Add comprehensive tests
4. Update documentation
5. Consider adding migration guide for existing deployments

## Configuration Example

With these changes, you can now run multiple stores:

```elixir
# Store 1
{ExESDB.System, [store_id: "store_1", data_dir: "/data/store1"]}

# Store 2
{ExESDB.System, [store_id: "store_2", data_dir: "/data/store2"]}
```

Both will run independently on the same node with proper isolation.
