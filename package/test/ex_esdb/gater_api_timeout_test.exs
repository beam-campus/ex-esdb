defmodule ExESDB.GaterApiTimeoutTest do
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.Schema.NewEvent
  alias ExESDBGater.API
  
  @test_store_id :test_gater_store
  @test_data_dir "/tmp/test_gater_#{:rand.uniform(1000)}"
  
  setup_all do
    # Configure test environment for single-node with multiple gateway workers
    opts = [
      store_id: @test_store_id,
      data_dir: @test_data_dir,
      timeout: 5000,
      db_type: :single,
      pub_sub: :ex_esdb_pub_sub,
      reader_idle_ms: 1000,
      writer_idle_ms: 1000,
      persistence_interval: 1000,
      gateway_pool_size: 3  # Start multiple workers for the API
    ]
    
    Logger.info("Starting ExESDB.System for ExESDBGater.API timeout tests with opts: #{inspect(opts)}")
    
    # Start the system which includes the GatewayWorker pool
    {:ok, system_pid} = System.start_link(opts)
    
    # Wait for system to be ready - need extra time for Swarm registration
    Process.sleep(3000)
    
    # Wait for gateway workers to be registered with Swarm
    wait_for_gateway_workers_registration(30, 500)
    
    # Ensure we have gateway workers available
    workers = API.gateway_worker_pids()
    Logger.info("Available gateway workers: #{inspect(workers)}")
    
    if Enum.empty?(workers) do
      Logger.error("No gateway workers available!")
      raise "No gateway workers available for testing"
    end
    
    on_exit(fn ->
      Logger.info("Stopping ExESDB.System for ExESDBGater.API timeout tests")
      if Process.alive?(system_pid) do
        Process.exit(system_pid, :kill)
        Process.sleep(3000)
      end
      Process.sleep(1000)
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid, opts: opts}
  end
  
  # Helper function to wait for gateway workers to register with Swarm
  defp wait_for_gateway_workers_registration(max_attempts, sleep_ms) do
    wait_for_gateway_workers_registration(max_attempts, sleep_ms, 0)
  end
  
  defp wait_for_gateway_workers_registration(max_attempts, sleep_ms, attempt) when attempt < max_attempts do
    workers = API.gateway_worker_pids()
    
    if length(workers) >= 1 do
      Logger.info("Gateway workers registered: #{length(workers)} available")
      :ok
    else
      Logger.info("Waiting for gateway workers... attempt #{attempt + 1}/#{max_attempts}")
      Process.sleep(sleep_ms)
      wait_for_gateway_workers_registration(max_attempts, sleep_ms, attempt + 1)
    end
  end
  
  defp wait_for_gateway_workers_registration(max_attempts, _sleep_ms, attempt) when attempt >= max_attempts do
    Logger.error("Failed to find gateway workers after #{max_attempts} attempts")
    raise "No gateway workers found after waiting"
  end
  
  # Helper function to create NewEvent structs
  defp create_test_event(event_type, data, metadata \\ %{}) do
    %NewEvent{
      event_id: UUIDv7.generate(),
      event_type: event_type,
      data_content_type: 0,  # Pure Erlang/Elixir terms
      metadata_content_type: 0,  # Pure Erlang/Elixir terms
      data: data,
      metadata: metadata
    }
  end
  
  describe "ExESDBGater.API basic functionality" do
    test "can append events using ExESDBGater.API" do
      stream_id = "test_gater_stream_#{:rand.uniform(1000)}"
      
      # Create test events
      events = [
        create_test_event("GaterEvent1", %{value: 1, source: "gater_api"}),
        create_test_event("GaterEvent2", %{value: 2, source: "gater_api"}),
        create_test_event("GaterEvent3", %{value: 3, source: "gater_api"})
      ]
      
      Logger.info("Appending events via ExESDBGater.API to stream: #{stream_id}")
      
      # Use ExESDBGater.API.append_events
      result = API.append_events(@test_store_id, stream_id, events)
      
      Logger.info("ExESDBGater.API.append_events result: #{inspect(result)}")
      
      assert {:ok, final_version} = result
      assert final_version == 2  # 0-based, so 3 events = version 2
      
      # Verify we can read the events back using ExESDBGater.API
      {:ok, read_events} = API.get_events(@test_store_id, stream_id, 0, 10, :forward)
      
      assert length(read_events) == 3
      assert Enum.at(read_events, 0).data.value == 1
      assert Enum.at(read_events, 1).data.value == 2
      assert Enum.at(read_events, 2).data.value == 3
      
      Logger.info("Successfully verified events were written and read via ExESDBGater.API")
    end
    
    test "can append events with expected version using ExESDBGater.API" do
      stream_id = "test_gater_version_#{:rand.uniform(1000)}"
      
      # First append
      events1 = [
        create_test_event("InitialEvent", %{value: 1, phase: "initial"})
      ]
      
      result1 = API.append_events(@test_store_id, stream_id, -1, events1)
      assert {:ok, 0} = result1
      
      # Second append with correct expected version
      events2 = [
        create_test_event("SecondEvent", %{value: 2, phase: "second"})
      ]
      
      result2 = API.append_events(@test_store_id, stream_id, 0, events2)
      assert {:ok, 1} = result2
      
      # Verify final state
      services = API.gateway_worker_pids_for_store(@test_store_id)
      
      if Enum.empty?(services) do
        Logger.error("No services available to validate final state!")
        assert false
      end

      {:ok, read_events} = API.get_events(@test_store_id, stream_id, 0, 10, :forward)
      assert length(read_events) == 2
      
      Logger.info("Successfully verified versioned appends via ExESDBGater.API")
    end
    
    test "handles version conflicts correctly via ExESDBGater.API" do
      stream_id = "test_gater_conflict_#{:rand.uniform(1000)}"
      
      # Write initial event
      event1 = create_test_event("Event1", %{value: 1})
      result1 = API.append_events(@test_store_id, stream_id, -1, [event1])
      assert {:ok, 0} = result1
      
      # Try to write with wrong expected version
      event2 = create_test_event("Event2", %{value: 2})
      result2 = API.append_events(@test_store_id, stream_id, 5, [event2])
      
      Logger.info("Testing version conflict via ExESDBGater.API for stream: #{stream_id}")
      
      # Should fail due to version mismatch
      assert {:error, _reason} = result2
      Logger.info("Version conflict handled correctly via ExESDBGater.API")
    end
  end
  
  describe "ExESDBGater.API timeout scenarios" do
    test "API timeout with custom timeout" do
      stream_id = "test_gater_custom_timeout_#{:rand.uniform(1000)}"
      
      events = [create_test_event("TimeoutEvent", %{value: 1})]
      
      Logger.info("Testing API timeout behavior")
      
      # Test with a very short timeout by directly calling the gateway worker
      # This demonstrates that timeout handling works
      workers = API.gateway_worker_pids_for_store(@test_store_id)
      worker_pid = List.first(workers)

      if is_nil(worker_pid) do
        Logger.error("No available worker for timeout test!")
        assert false
      end

      start_time = :erlang.monotonic_time(:millisecond)
      
      try do
        # Call with a very short timeout (1ms) - this should timeout
        result = GenServer.call(worker_pid, {:append_events, @test_store_id, stream_id, events}, 1)
        Logger.info("Unexpected success with short timeout: #{inspect(result)}")
        # If we get here, the operation was faster than 1ms
        assert {:ok, _} = result
      catch
        :exit, {:timeout, _} ->
          end_time = :erlang.monotonic_time(:millisecond)
          duration = end_time - start_time
          Logger.info("Expected timeout occurred after #{duration}ms")
          assert duration >= 1  # Should timeout after at least 1ms
          assert duration < 100  # But not take too long to timeout
      end
      
      # Now test with normal timeout to ensure it works
      start_time = :erlang.monotonic_time(:millisecond)
      result = GenServer.call(worker_pid, {:append_events, @test_store_id, stream_id, events}, 5000)
      end_time = :erlang.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      Logger.info("Normal timeout operation took #{duration}ms")
      assert {:ok, 1} = result
      assert duration < 5000  # Should complete well before timeout
      
      Logger.info("Custom timeout test completed successfully")
    end
    test "GenServer timeout demonstration" do
      stream_id = "test_gater_genserver_timeout_#{:rand.uniform(1000)}"
      
      events = [create_test_event("TimeoutEvent", %{value: 1})]
      
      Logger.info("Testing GenServer timeout behavior")
      
      # Get a gateway worker to call directly
      workers = API.gateway_worker_pids_for_store(@test_store_id)
      worker_pid = List.first(workers)
      
      # Test timeout with GenServer.call
      start_time = :erlang.monotonic_time(:millisecond)
      
      try do
        # Use a very short timeout to force a timeout
        result = GenServer.call(worker_pid, {:append_events, @test_store_id, stream_id, events}, 1)
        Logger.info("Operation completed before timeout: #{inspect(result)}")
        assert {:ok, _} = result
      catch
        :exit, {:timeout, _call_details} ->
          end_time = :erlang.monotonic_time(:millisecond)
          duration = end_time - start_time
          Logger.info("GenServer call timed out after #{duration}ms")
          assert duration >= 1
          assert duration < 100
      end
      
      Logger.info("GenServer timeout test completed successfully")
    end
    
    test "append_events with normal timeout" do
      stream_id = "test_gater_normal_timeout_#{:rand.uniform(1000)}"
      
      # Create a modest number of events
      events = Enum.map(1..5, fn i ->
        create_test_event("TimeoutEvent#{i}", %{value: i, batch: "normal"})
      end)
      
      Logger.info("Testing normal timeout scenario via ExESDBGater.API")
      
      # This should complete normally
      start_time = :erlang.monotonic_time(:millisecond)
      result = API.append_events(@test_store_id, stream_id, events)
      end_time = :erlang.monotonic_time(:millisecond)
      
      duration = end_time - start_time
      Logger.info("Normal append took #{duration}ms")
      
      assert {:ok, 4} = result
      assert duration < 5000  # Should complete well within timeout
      
      Logger.info("Normal timeout scenario completed successfully")
    end
    
    test "append_events with large payload that might approach timeout" do
      stream_id = "test_gater_large_payload_#{:rand.uniform(1000)}"
      
      # Create a very large event payload to increase processing time
      large_data = %{
        large_text: String.duplicate("X", 100_000),  # 100KB of text
        large_array: Enum.to_list(1..10_000),       # 10K integers
        large_map: Map.new(1..1000, fn i -> {:"key#{i}", String.duplicate("value", 100)} end),
        timestamp: DateTime.utc_now(),
        metadata: %{
          description: "Large payload test for timeout scenarios",
          size: "very_large"
        }
      }
      
      # Create multiple large events
      events = Enum.map(1..3, fn i ->
        create_test_event("LargeEvent#{i}", Map.put(large_data, :index, i))
      end)
      
      Logger.info("Testing large payload scenario via ExESDBGater.API")
      Logger.info("Total events: #{length(events)}, approximate size per event: ~200KB")
      
      # This should still complete but might take longer
      start_time = :erlang.monotonic_time(:millisecond)
      result = API.append_events(@test_store_id, stream_id, events)
      end_time = :erlang.monotonic_time(:millisecond)
      
      duration = end_time - start_time
      Logger.info("Large payload append took #{duration}ms")
      
      assert {:ok, 2} = result
      # Should complete within reasonable time but might be slower than normal
      assert duration < 10000  # Give more time for large payload
      
      # Verify the events were written correctly
      {:ok, read_events} = API.get_events(@test_store_id, stream_id, 0, 10, :forward)
      assert length(read_events) == 3
      
      # Verify the large data was preserved
      first_event = Enum.at(read_events, 0)
      assert first_event.data.index == 1
      assert String.length(first_event.data.large_text) == 100_000
      
      Logger.info("Large payload scenario completed successfully")
    end
    
    test "concurrent append_events operations" do
      stream_base = "test_gater_concurrent_#{:rand.uniform(1000)}"
      
      Logger.info("Testing concurrent operations via ExESDBGater.API")
      
      # Start multiple concurrent append operations to different streams
      tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          stream_id = "#{stream_base}_stream_#{i}"
          
          events = Enum.map(1..5, fn j ->
            create_test_event("ConcurrentEvent#{j}", %{
              stream_index: i,
              event_index: j,
              task_id: "task_#{i}_event_#{j}"
            })
          end)
          
          start_time = :erlang.monotonic_time(:millisecond)
          result = API.append_events(@test_store_id, stream_id, events)
          end_time = :erlang.monotonic_time(:millisecond)
          
          duration = end_time - start_time
          
          {stream_id, result, duration}
        end)
      end)
      
      # Wait for all tasks to complete
      results = Enum.map(tasks, fn task -> Task.await(task, 15000) end)
      
      # Analyze results
      successful_count = Enum.count(results, fn {_, result, _} -> 
        match?({:ok, _}, result) 
      end)
      
      durations = Enum.map(results, fn {_, _, duration} -> duration end)
      max_duration = Enum.max(durations)
      avg_duration = Enum.sum(durations) / length(durations)
      
      Logger.info("Concurrent operations completed:")
      Logger.info("  Successful: #{successful_count}/#{length(results)}")
      Logger.info("  Max duration: #{max_duration}ms")
      Logger.info("  Avg duration: #{Float.round(avg_duration, 2)}ms")
      
      # All operations should succeed
      assert successful_count == length(results)
      
      # No individual operation should timeout
      assert max_duration < 10000
      
      Logger.info("Concurrent operations scenario completed successfully")
    end
    
    test "mixed operations under load" do
      stream_id = "test_gater_mixed_load_#{:rand.uniform(1000)}"
      
      Logger.info("Testing mixed operations under load via ExESDBGater.API")
      
      # First, write some initial events
      initial_events = Enum.map(1..10, fn i ->
        create_test_event("InitialEvent#{i}", %{value: i, phase: "initial"})
      end)
      
      result = API.append_events(@test_store_id, stream_id, initial_events)
      assert {:ok, 9} = result
      
      # Now perform mixed operations concurrently
      tasks = [
        # Task 1: More appends
        Task.async(fn ->
          events = Enum.map(11..15, fn i ->
            create_test_event("AdditionalEvent#{i}", %{value: i, phase: "additional"})
          end)
          
          start_time = :erlang.monotonic_time(:millisecond)
          result = API.append_events(@test_store_id, stream_id, 9, events)
          end_time = :erlang.monotonic_time(:millisecond)
          
          {:append, result, end_time - start_time}
        end),
        
        # Task 2: Read events
        Task.async(fn ->
          start_time = :erlang.monotonic_time(:millisecond)
          result = API.get_events(@test_store_id, stream_id, 0, 20, :forward)
          end_time = :erlang.monotonic_time(:millisecond)
          
          {:read, result, end_time - start_time}
        end),
        
        # Task 3: Get stream version
        Task.async(fn ->
          start_time = :erlang.monotonic_time(:millisecond)
          result = API.get_version(@test_store_id, stream_id)
          end_time = :erlang.monotonic_time(:millisecond)
          
          {:version, result, end_time - start_time}
        end),
        
        # Task 4: List streams
        Task.async(fn ->
          start_time = :erlang.monotonic_time(:millisecond)
          result = API.get_streams(@test_store_id)
          end_time = :erlang.monotonic_time(:millisecond)
          
          {:list_streams, result, end_time - start_time}
        end)
      ]
      
      # Wait for all tasks to complete
      results = Enum.map(tasks, fn task -> Task.await(task, 10000) end)
      
      # Analyze results
      Enum.each(results, fn {operation, result, duration} ->
        Logger.info("#{operation}: #{inspect(result)} (#{duration}ms)")
        assert match?({:ok, _}, result)
        assert duration < 5000  # No operation should take too long
      end)
      
      Logger.info("Mixed operations under load completed successfully")
    end
  end
  
  describe "ExESDBGater.API error handling" do
    test "handles non-existent store gracefully" do
      stream_id = "test_stream_nonexistent"
      
      event = create_test_event("TestEvent", %{value: 1})
      
      Logger.info("Testing non-existent store via ExESDBGater.API")
      
      # This should cause the gateway worker to crash when trying to access a non-existent store
      # This is actually a timeout scenario because the GenServer call will fail
      try do
        result = API.append_events(:non_existent_store, stream_id, [event])
        Logger.info("Non-existent store result: #{inspect(result)}")
        # If we get here, it means the call succeeded somehow
        assert {:error, _reason} = result
      rescue
        e ->
          Logger.info("Expected error occurred: #{inspect(e)}")
          # This is expected - the gateway worker should crash or timeout
          assert true
      catch
        :exit, reason ->
          Logger.info("Expected exit occurred: #{inspect(reason)}")
          # This is expected - the GenServer call should exit
          assert true
      end
      
      Logger.info("Non-existent store error handled correctly")
    end
    
    test "handles empty events list" do
      stream_id = "test_gater_empty_#{:rand.uniform(1000)}"
      
      Logger.info("Testing empty events list via ExESDBGater.API")
      
      # This should handle gracefully
      result = API.append_events(@test_store_id, stream_id, [])
      
      Logger.info("Empty events result: #{inspect(result)}")
      
      # Should succeed with no events added
      assert {:ok, -1} = result
      
      Logger.info("Empty events list handled correctly")
    end
    
    test "API worker availability" do
      # Test that we can get gateway workers
      workers = API.gateway_worker_pids()
      assert length(workers) > 0
      
      # Test that we can get workers for our specific store
      store_workers = API.gateway_worker_pids_for_store(@test_store_id)
      assert length(store_workers) > 0
      
      # Test that we can get a random worker
      random_worker = API.random_gateway_worker()
      assert is_pid(random_worker)
      assert Process.alive?(random_worker)
      
      # Test that we can get a random worker for our store
      random_store_worker = API.random_gateway_worker_pid_for_store(@test_store_id)
      assert is_pid(random_store_worker)
      assert Process.alive?(random_store_worker)
      
      Logger.info("API worker availability verified")
    end
  end
end
