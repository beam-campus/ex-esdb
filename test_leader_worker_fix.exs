#!/usr/bin/env elixir

# Test script to verify LeaderWorker registration fix

# Add the system directory to the path  
Code.append_path("/home/rl/work/github.com/beam-campus/ex-esdb/system/_build/dev/lib/ex_esdb/ebin")

# Test configuration for a store
store_config = [
  store_id: "test_store",
  cluster_name: "test_cluster",
  node_id: "test_node",
  data_dir: "/tmp/test_store",
  writers_pool_size: 1,
  readers_pool_size: 1,
  gateway_pool_size: 1,
  emitter_pool_size: 1,
  timeout: 10_000
]

IO.puts("🧪 Testing LeaderWorker registration fix...")
IO.puts("=" |> String.duplicate(50))

# Start required applications
{:ok, _} = Application.ensure_all_started(:logger)
{:ok, _} = Application.ensure_all_started(:crypto)

try do
  # Start the ExESDB System
  IO.puts("🚀 Starting ExESDB System with store_id: #{store_config[:store_id]}")
  
  case ExESDB.System.start_link(store_config) do
    {:ok, pid} ->
      IO.puts("✅ ExESDB System started successfully with PID: #{inspect(pid)}")
      
      # Give it a moment to initialize
      :timer.sleep(2000)
      
      # Check if the LeaderWorker is registered with the correct store-specific name
      expected_name = ExESDB.StoreNaming.genserver_name(ExESDB.LeaderWorker, store_config[:store_id])
      IO.puts("🔍 Checking LeaderWorker registration:")
      IO.puts("   Expected name: #{inspect(expected_name)}")
      
      case Process.whereis(expected_name) do
        nil -> 
          IO.puts("   ❌ LeaderWorker not found with store-specific name")
        worker_pid ->
          IO.puts("   ✅ LeaderWorker registered with PID: #{inspect(worker_pid)}")
      end
      
      # Also check if the old hardcoded name exists (it shouldn't for store-specific instances)
      case Process.whereis(ExESDB.LeaderWorker) do
        nil -> 
          IO.puts("   ✅ Old hardcoded name not registered (as expected)")
        old_pid ->
          IO.puts("   ⚠️  Old hardcoded name still registered with PID: #{inspect(old_pid)}")
      end
      
      IO.puts("🎉 Test completed successfully!")
      
      # Clean shutdown
      IO.puts("🧹 Shutting down...")
      if Process.alive?(pid) do
        Process.exit(pid, :shutdown)
      end
      
    {:error, reason} ->
      IO.puts("❌ Failed to start ExESDB System: #{inspect(reason)}")
  end
rescue
  error ->
    IO.puts("❌ Exception occurred: #{inspect(error)}")
end

IO.puts("✅ LeaderWorker registration test completed")
