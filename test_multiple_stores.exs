#!/usr/bin/env elixir

# Test script to verify multiple ExESDB stores can start without naming conflicts

# Add the system directory to the path
Code.append_path("/home/rl/work/github.com/beam-campus/ex-esdb/system/_build/dev/lib/ex_esdb/ebin")

# Load the ExESDB application
Application.load(:ex_esdb)

# Start required applications
{:ok, _} = Application.ensure_all_started(:logger)
{:ok, _} = Application.ensure_all_started(:crypto)

# Test configuration for multiple stores
store_configs = [
  [
    store_id: "store_one",
    cluster_name: "cluster_one",
    node_id: "node_one",
    data_dir: "/tmp/store_one",
    writers_pool_size: 2,
    readers_pool_size: 2,
    gateway_pool_size: 1,
    emitter_pool_size: 1,
    timeout: 30_000
  ],
  [
    store_id: "store_two", 
    cluster_name: "cluster_two",
    node_id: "node_two",
    data_dir: "/tmp/store_two",
    writers_pool_size: 2,
    readers_pool_size: 2,
    gateway_pool_size: 1,
    emitter_pool_size: 1,
    timeout: 30_000
  ]
]

IO.puts("🧪 Testing multiple ExESDB stores startup...")
IO.puts("=" |> String.duplicate(50))

# Function to start a store and check for conflicts
test_store_startup = fn config ->
  store_id = Keyword.get(config, :store_id)
  IO.puts("🚀 Starting store: #{store_id}")
  
  try do
    # Start the ExESDB System for this store
    case ExESDB.System.start_link(config) do
      {:ok, pid} ->
        IO.puts("✅ Successfully started store #{store_id} with PID: #{inspect(pid)}")
        
        # Check if the store-specific processes are running
        partition_processes = [
          ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, store_id),
          ExESDB.StoreNaming.partition_name(ExESDB.StreamsReaders, store_id),
          ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsWriters, store_id),
          ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsReaders, store_id),
          ExESDB.StoreNaming.partition_name(ExESDB.EmitterPools, store_id),
          ExESDB.StoreNaming.partition_name(ExESDB.GatewayWorkers, store_id)
        ]
        
        IO.puts("🔍 Checking store-specific processes:")
        Enum.each(partition_processes, fn process_name ->
          case Process.whereis(process_name) do
            nil -> IO.puts("   ❌ #{process_name} not found")
            pid -> IO.puts("   ✅ #{process_name} running with PID: #{inspect(pid)}")
          end
        end)
        
        {:ok, pid}
        
      {:error, {:already_started, pid}} ->
        IO.puts("⚠️  Store #{store_id} already started with PID: #{inspect(pid)}")
        {:ok, pid}
        
      {:error, reason} ->
        IO.puts("❌ Failed to start store #{store_id}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      IO.puts("❌ Exception starting store #{store_id}: #{inspect(error)}")
      {:error, error}
  end
end

# Test starting multiple stores
results = Enum.map(store_configs, test_store_startup)

# Summary
IO.puts("\n" <> ("=" |> String.duplicate(50)))
IO.puts("📊 Test Summary:")

success_count = Enum.count(results, fn
  {:ok, _} -> true
  _ -> false
end)

IO.puts("✅ Successfully started stores: #{success_count}/#{length(store_configs)}")

if success_count == length(store_configs) do
  IO.puts("🎉 All stores started successfully - no naming conflicts detected!")
else
  IO.puts("⚠️  Some stores failed to start - check logs above")
end

# Give some time for processes to settle
:timer.sleep(2000)

# Check if all processes are still running
IO.puts("\n🔍 Final process check:")
all_running = Enum.all?(results, fn
  {:ok, pid} -> Process.alive?(pid)
  _ -> false
end)

if all_running do
  IO.puts("✅ All store processes are still running")
else
  IO.puts("❌ Some store processes have terminated")
end

# Clean shutdown
IO.puts("\n🧹 Cleaning up...")
Enum.each(results, fn
  {:ok, pid} -> 
    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end
  _ -> :ok
end)

IO.puts("✅ Test completed")
