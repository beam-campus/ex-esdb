# ExESDB Multiple Stores Naming Conflicts Fix

## Problem Summary

When multiple umbrella applications attempted to start their own ExESDB systems, they encountered `already started` errors due to hardcoded process names in supervisor start calls. The conflicting processes were:

- `ExESDB.StreamsWriters`
- `ExESDB.StreamsReaders`
- `ExESDB.SnapshotsWriters`
- `ExESDB.SnapshotsReaders`
- `ExESDB.EmitterPools`
- `ExESDB.GatewayWorkers`

## Solution

Updated all modules to use the `ExESDB.StoreNaming.partition_name/2` helper function, which generates store-specific atoms for these global names.

## Files Modified

### 1. **ExESDB.Emitters** (`lib/ex_esdb/emitters.ex`)
- **Change**: Updated `start_emitter_pool/3` to use store-specific partition names
- **Before**: `{ExESDB.EmitterPools, partition(args)}`
- **After**: `{StoreNaming.partition_name(ExESDB.EmitterPools, store), partition(args)}`

### 2. **ExESDB.EmitterSystem** (`lib/ex_esdb/emitter_system.ex`)
- **Change**: Updated supervisor child spec to use store-specific partition names
- **Before**: `name: ExESDB.EmitterPools`
- **After**: `name: StoreNaming.partition_name(ExESDB.EmitterPools, store_id)`

### 3. **ExESDB.GatewaySystem** (`lib/ex_esdb/gateway_system.ex`)
- **Change**: Updated supervisor child spec to use store-specific partition names
- **Before**: `name: ExESDB.GatewayWorkers`
- **After**: `name: StoreNaming.partition_name(ExESDB.GatewayWorkers, store_id)`

### 4. **ExESDB.LeaderWorker** (`lib/ex_esdb/leader_worker.ex`)
- **Change**: Updated process lookup to use store-specific partition names
- **Before**: `Process.whereis(ExESDB.EmitterPools)`
- **After**: `Process.whereis(StoreNaming.partition_name(ExESDB.EmitterPools, store))`

### 5. **ExESDB.Snapshots** (`lib/ex_esdb/snapshots.ex`)
- **Change**: Updated supervisor child specs to use store-specific partition names
- **Before**: `name: ExESDB.SnapshotsWriters` and `name: ExESDB.SnapshotsReaders`
- **After**: `name: StoreNaming.partition_name(ExESDB.SnapshotsWriters, store_id)` and `name: StoreNaming.partition_name(ExESDB.SnapshotsReaders, store_id)`

### 6. **ExESDB.SnapshotsReader** (`lib/ex_esdb/snapshots_reader.ex`)
- **Change**: Updated `start_child/2` to use store-specific partition names
- **Before**: `{ExESDB.SnapshotsReaders, partition(args)}`
- **After**: `{StoreNaming.partition_name(ExESDB.SnapshotsReaders, store), partition(args)}`

### 7. **ExESDB.SnapshotsWriter** (`lib/ex_esdb/snapshots_writer.ex`)
- **Change**: Updated `start_child/2` to use store-specific partition names
- **Before**: `{ExESDB.SnapshotsWriters, partition(args)}`
- **After**: `{StoreNaming.partition_name(ExESDB.SnapshotsWriters, store), partition(args)}`

### 8. **ExESDB.Streams** (`lib/ex_esdb/streams.ex`)
- **Change**: Updated supervisor child specs to use store-specific partition names
- **Before**: `name: ExESDB.StreamsWriters` and `name: ExESDB.StreamsReaders`
- **After**: `name: StoreNaming.partition_name(ExESDB.StreamsWriters, store_id)` and `name: StoreNaming.partition_name(ExESDB.StreamsReaders, store_id)`

### 9. **ExESDB.StreamsReader** (`lib/ex_esdb/streams_reader.ex`)
- **Change**: Updated `start_child/2` to use store-specific partition names
- **Before**: `{ExESDB.StreamsReaders, partition(args)}`
- **After**: `{StoreNaming.partition_name(ExESDB.StreamsReaders, store), partition(args)}`

### 10. **ExESDB.StreamsWriter** (`lib/ex_esdb/streams_writer.ex`)
- **Change**: Updated `start_child/2` to use store-specific partition names
- **Before**: `{ExESDB.StreamsWriters, partition(args)}`
- **After**: `{StoreNaming.partition_name(ExESDB.StreamsWriters, store), partition(args)}`

## How the Fix Works

The `ExESDB.StoreNaming.partition_name/2` function generates unique process names by combining the base name with the store ID:

```elixir
# For store_id = "my_store"
ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, "my_store")
# Returns: :exesdb_streamswriters_my_store

ExESDB.StoreNaming.partition_name(ExESDB.StreamsReaders, "my_store")
# Returns: :exesdb_streamsreaders_my_store
```

## Backward Compatibility

The fix maintains backward compatibility:
- When `store_id` is `nil`, the function returns the original module name
- Existing single-store deployments continue to work unchanged
- The naming pattern is consistent across all modules

## Testing

Created test script (`test_partition_names.exs`) which verifies:
- ✅ Store-specific partition names are generated correctly
- ✅ Names are unique between different stores
- ✅ Backward compatibility works (nil returns original names)
- ✅ All partition types are properly handled

## Expected Outcome

After these changes, multiple umbrella applications can start their own ExESDB systems without naming conflicts. Each store will have its own isolated set of partition supervisors:

- Store "app_one": `:exesdb_streamswriters_app_one`, `:exesdb_streamsreaders_app_one`, etc.
- Store "app_two": `:exesdb_streamswriters_app_two`, `:exesdb_streamsreaders_app_two`, etc.

This allows true multi-tenancy where different applications can maintain completely separate event stores within the same Elixir node.
