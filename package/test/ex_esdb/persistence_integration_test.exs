defmodule ExESDB.PersistenceIntegrationTest do
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.StreamsReader
  alias ExESDB.PersistenceWorker
  alias ExESDB.Schema.NewEvent
  alias ExESDB.Store
  alias ExESDB.StoreNaming
  
  @test_store_id :test_persistence_store
  @test_data_dir "/tmp/test_persistence_#{:rand.uniform(1000)}"
  
  setup_all do
    # Configure test environment for single-node (no clustering)
    opts = [
      store_id: @test_store_id,
      data_dir: @test_data_dir,
      timeout: 5000,
      db_type: :single,
      pub_sub: :ex_esdb_pub_sub,  # Use the default registry name
      reader_idle_ms: 1000,
      writer_idle_ms: 1000,
      persistence_interval: 1000  # Short interval for testing
    ]
    
    Logger.info("Starting ExESDB.System for persistence integration tests with opts: #{inspect(opts)}")
    
    # Start the system
    {:ok, system_pid} = System.start_link(opts)
    
    # Wait for system to be ready
    Process.sleep(2000)
    
    on_exit(fn ->
      Logger.info("Stopping ExESDB.System for persistence integration tests")
      if Process.alive?(system_pid) do
        try do
          GenServer.stop(system_pid, :normal, 10000)
        rescue
          e -> Logger.warning("Error stopping system: #{inspect(e)}")
        end
      end
      # Clean up any remaining processes
      Process.sleep(1000)
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid, opts: opts}
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
  
  # Helper function to get store GenServer name
  defp get_store_name(store_id) do
    StoreNaming.genserver_name(ExESDB.Store, store_id)
  end
  
  # Helper function to restart store while preserving data
  defp restart_store_gracefully(store_id) do
    store_name = get_store_name(store_id)
    
    # Get store process
    store_pid = GenServer.whereis(store_name)
    
    if store_pid do
      # Stop store gracefully
      GenServer.stop(store_pid, :normal, 5000)
      
      # Wait for process to terminate
      Process.sleep(1000)
      
      # Wait for the process to actually be unregistered
      Process.sleep(2000)
      
      # The store might still be registered due to supervisor restart
      # Let's check if it's actually stopped by checking if it's responsive
      case GenServer.whereis(store_name) do
        nil -> :ok
        pid -> 
          # If still registered, force kill it
          Process.exit(pid, :kill)
          Process.sleep(1000)
      end
    end
    
    # Start store again with same configuration
    opts = [
      store_id: store_id,
      data_dir: @test_data_dir,
      timeout: 5000
    ]
    
    {:ok, new_pid} = Store.start_link(opts)
    Process.sleep(2000)
    
    new_pid
  end
  
  # Helper function to force stop store (simulate crash)
  defp crash_store(store_id) do
    store_name = get_store_name(store_id)
    store_pid = GenServer.whereis(store_name)
    
    if store_pid do
      Process.exit(store_pid, :kill)
      Process.sleep(1000)
    end
    
    # Verify store is stopped
    assert GenServer.whereis(store_name) == nil
  end
  
  describe "event writing and persistence flow" do
    test "writes events and triggers persistence requests" do
      stream_id = "test_stream_persist_#{:rand.uniform(1000)}"
      
      # Create test events
      events = [
        create_test_event("Event1", %{value: 1, timestamp: DateTime.utc_now()}),
        create_test_event("Event2", %{value: 2, timestamp: DateTime.utc_now()}),
        create_test_event("Event3", %{value: 3, timestamp: DateTime.utc_now()})
      ]
      
      Logger.info("Writing events to stream: #{stream_id}")
      
      # Write events - this should trigger persistence requests
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 2} = result
      
      Logger.info("Successfully wrote events, verifying persistence was requested")
      
      # Verify events can be read back
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 3
      assert Enum.at(read_events, 0).data.value == 1
      assert Enum.at(read_events, 1).data.value == 2
      assert Enum.at(read_events, 2).data.value == 3
      
      Logger.info("Successfully verified events were written and can be read back")
    end
    
    test "persistence worker handles multiple stores" do
      # Create multiple streams across different "stores" (same actual store, but different persistence requests)
      streams = [
        {"stream_1_#{:rand.uniform(1000)}", %{store_type: "orders"}},
        {"stream_2_#{:rand.uniform(1000)}", %{store_type: "inventory"}},
        {"stream_3_#{:rand.uniform(1000)}", %{store_type: "customers"}}
      ]
      
      Logger.info("Writing to multiple streams to test persistence worker batching")
      
      # Write to all streams
      Enum.each(streams, fn {stream_id, metadata} ->
        event = create_test_event("TestEvent", %{data: "test"}, metadata)
        result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [event])
        assert {:ok, 0} = result
      end)
      
      # Request persistence for the store
      result = PersistenceWorker.request_persistence(@test_store_id)
      assert result == :ok
      
      Logger.info("Successfully requested persistence for multiple streams")
      
      # Verify all streams can be read
      Enum.each(streams, fn {stream_id, _metadata} ->
        {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
        read_events = Enum.to_list(event_stream)
        assert length(read_events) == 1
      end)
      
      Logger.info("Successfully verified all streams are accessible")
    end
    
    test "force persistence works synchronously" do
      stream_id = "test_stream_force_persist_#{:rand.uniform(1000)}"
      
      # Write some events
      events = Enum.map(1..5, fn i ->
        create_test_event("Event#{i}", %{value: i, batch: "force_test"})
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 4} = result
      
      Logger.info("Written events, forcing persistence")
      
      # Force persistence - this should complete synchronously
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      Logger.info("Force persistence completed successfully")
      
      # Verify events are still accessible
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 5
      
      # Verify order
      values = Enum.map(read_events, fn event -> event.data.value end)
      assert values == [1, 2, 3, 4, 5]
      
      Logger.info("Successfully verified events after force persistence")
    end
  end
  
  describe "store recovery scenarios" do
    test "data survives graceful store restart" do
      stream_id = "test_stream_recovery_#{:rand.uniform(1000)}"
      
      # Write test data
      events = [
        create_test_event("PreRestart1", %{value: 1, phase: "before_restart"}),
        create_test_event("PreRestart2", %{value: 2, phase: "before_restart"})
      ]
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 1} = result
      
      # Force persistence to ensure data is on disk
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      Logger.info("Data written and persisted, restarting store gracefully")
      
      # Restart store gracefully
      new_store_pid = restart_store_gracefully(@test_store_id)
      assert Process.alive?(new_store_pid)
      
      # Wait for store to be ready
      Process.sleep(2000)
      
      Logger.info("Store restarted, verifying data recovery")
      
      # Verify data is still accessible
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 2
      assert Enum.at(read_events, 0).data.value == 1
      assert Enum.at(read_events, 1).data.value == 2
      
      # Verify we can append to the recovered stream
      new_event = create_test_event("PostRestart", %{value: 3, phase: "after_restart"})
      append_result = StreamsWriter.append_events(@test_store_id, stream_id, 1, [new_event])
      assert {:ok, 2} = append_result
      
      Logger.info("Successfully recovered data and appended new event after restart")
      
      # Verify final state
      {:ok, final_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      final_events = Enum.to_list(final_stream)
      
      assert length(final_events) == 3
      assert Enum.at(final_events, 2).data.value == 3
      assert Enum.at(final_events, 2).data.phase == "after_restart"
      
      Logger.info("Successfully verified complete recovery scenario")
    end
    
    test "handles multiple streams recovery" do
      # Create multiple streams with different data
      streams_data = [
        {"recovery_stream_1_#{:rand.uniform(1000)}", [
          create_test_event("Type1", %{id: 1, category: "orders"}),
          create_test_event("Type1", %{id: 2, category: "orders"})
        ]},
        {"recovery_stream_2_#{:rand.uniform(1000)}", [
          create_test_event("Type2", %{id: 1, category: "inventory"}),
          create_test_event("Type2", %{id: 2, category: "inventory"}),
          create_test_event("Type2", %{id: 3, category: "inventory"})
        ]},
        {"recovery_stream_3_#{:rand.uniform(1000)}", [
          create_test_event("Type3", %{id: 1, category: "customers"})
        ]}
      ]
      
      # Write all streams
      Enum.each(streams_data, fn {stream_id, events} ->
        result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
        assert {:ok, _} = result
      end)
      
      # Force persistence
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      Logger.info("Written multiple streams, forcing persistence and restarting")
      
      # Restart store
      new_store_pid = restart_store_gracefully(@test_store_id)
      assert Process.alive?(new_store_pid)
      Process.sleep(2000)
      
      Logger.info("Store restarted, verifying recovery of all streams")
      
      # Verify all streams recovered correctly
      Enum.each(streams_data, fn {stream_id, original_events} ->
        {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
        read_events = Enum.to_list(event_stream)
        
        assert length(read_events) == length(original_events)
        
        # Verify event types match
        original_types = Enum.map(original_events, fn event -> event.event_type end)
        recovered_types = Enum.map(read_events, fn event -> event.event_type end)
        assert recovered_types == original_types
        
        Logger.info("Successfully verified recovery of stream: #{stream_id}")
      end)
      
      Logger.info("Successfully verified recovery of all streams")
    end
    
    test "handles concurrent operations during recovery" do
      stream_id = "test_concurrent_recovery_#{:rand.uniform(1000)}"
      
      # Write initial data
      initial_events = Enum.map(1..10, fn i ->
        create_test_event("Initial#{i}", %{value: i, batch: "initial"})
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, initial_events)
      assert {:ok, 9} = result
      
      # Force persistence
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      Logger.info("Initial data written, testing concurrent operations after restart")
      
      # Restart store
      new_store_pid = restart_store_gracefully(@test_store_id)
      assert Process.alive?(new_store_pid)
      Process.sleep(2000)
      
      # Start concurrent append operations
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          # Each task appends to the stream with proper version
          # We need to handle version conflicts properly
          event = create_test_event("Concurrent#{i}", %{value: i + 100, batch: "concurrent"})
          
          # Try to append - some may fail due to version conflicts, which is expected
          case StreamsWriter.append_events(@test_store_id, stream_id, 9 + i - 1, [event]) do
            {:ok, version} -> {:ok, version}
            {:error, reason} -> {:error, reason}
          end
        end)
      end)
      
      # Wait for all tasks and collect results
      results = Enum.map(tasks, &Task.await/1)
      
      # At least one should succeed
      successful_results = Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      assert length(successful_results) >= 1
      
      Logger.info("Concurrent operations completed, verifying final state")
      
      # Verify final state
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 20, :forward)
      read_events = Enum.to_list(event_stream)
      
      # Should have at least the initial 10 events plus at least 1 concurrent event
      assert length(read_events) >= 11
      
      # Verify initial events are still there
      initial_recovered = Enum.take(read_events, 10)
      initial_values = Enum.map(initial_recovered, fn event -> event.data.value end)
      assert initial_values == Enum.to_list(1..10)
      
      Logger.info("Successfully verified concurrent operations during recovery")
    end
  end
  
  describe "persistence worker integration" do
    test "persistence worker stats tracking" do
      # Get initial stats
      initial_stats = PersistenceWorker.get_stats(@test_store_id)
      assert {:ok, stats} = initial_stats
      
      Logger.info("Initial persistence worker stats: #{inspect(stats)}")
      
      # Write some events to trigger persistence requests
      stream_id = "test_stats_#{:rand.uniform(1000)}"
      events = Enum.map(1..3, fn i ->
        create_test_event("StatsEvent#{i}", %{value: i})
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 2} = result
      
      # Request persistence
      request_result = PersistenceWorker.request_persistence(@test_store_id)
      assert request_result == :ok
      
      # Force persistence to ensure it completes
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      # Get updated stats
      updated_stats = PersistenceWorker.get_stats(@test_store_id)
      assert {:ok, new_stats} = updated_stats
      
      Logger.info("Updated persistence worker stats: #{inspect(new_stats)}")
      
      # Verify stats have been updated
      assert new_stats.total_requests > stats.total_requests
      assert new_stats.successful_requests > stats.successful_requests
      assert new_stats.last_success_time != nil
      
      Logger.info("Successfully verified persistence worker stats tracking")
    end
    
    test "persistence worker handles errors gracefully" do
      # We can't easily simulate khepri errors without mocking, but we can test the API
      
      # Test requesting persistence for non-existent store
      result = PersistenceWorker.request_persistence(:non_existent_store)
      assert result == :error
      
      # Test forcing persistence for non-existent store
      force_result = PersistenceWorker.force_persistence(:non_existent_store)
      assert force_result == :error
      
      # Test getting stats for non-existent store
      stats_result = PersistenceWorker.get_stats(:non_existent_store)
      assert stats_result == :error
      
      Logger.info("Successfully verified persistence worker error handling")
    end
  end
  
  describe "data integrity scenarios" do
    test "verifies data integrity after persistence operations" do
      stream_id = "test_integrity_#{:rand.uniform(1000)}"
      
      # Write a batch of events with specific data
      events = Enum.map(1..20, fn i ->
        create_test_event("IntegrityEvent#{i}", %{
          value: i,
          checksum: :crypto.hash(:md5, "#{i}"),
          timestamp: DateTime.utc_now(),
          metadata: %{sequence: i, batch: "integrity_test"}
        })
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 19} = result
      
      # Force persistence
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      # Read all events and verify integrity
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 25, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 20
      
      # Verify each event's integrity
      Enum.each(read_events, fn event ->
        expected_checksum = :crypto.hash(:md5, "#{event.data.value}")
        assert event.data.checksum == expected_checksum
        assert event.data.metadata.sequence == event.data.value
        assert event.data.metadata.batch == "integrity_test"
      end)
      
      Logger.info("Successfully verified data integrity after persistence")
      
      # Restart store and verify integrity again
      new_store_pid = restart_store_gracefully(@test_store_id)
      assert Process.alive?(new_store_pid)
      Process.sleep(2000)
      
      # Read events after restart
      {:ok, recovered_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 25, :forward)
      recovered_events = Enum.to_list(recovered_stream)
      
      assert length(recovered_events) == 20
      
      # Verify integrity again
      Enum.each(recovered_events, fn event ->
        expected_checksum = :crypto.hash(:md5, "#{event.data.value}")
        assert event.data.checksum == expected_checksum
        assert event.data.metadata.sequence == event.data.value
        assert event.data.metadata.batch == "integrity_test"
      end)
      
      Logger.info("Successfully verified data integrity after recovery")
    end
    
    test "handles large event payloads with persistence" do
      stream_id = "test_large_payload_#{:rand.uniform(1000)}"
      
      # Create a large event payload
      large_data = %{
        large_text: String.duplicate("X", 50_000),
        large_array: Enum.to_list(1..5000),
        large_map: Map.new(1..1000, fn i -> {:"key#{i}", "value#{i}"} end),
        timestamp: DateTime.utc_now(),
        checksum: :crypto.hash(:sha256, "large_payload_test")
      }
      
      large_event = create_test_event("LargeEvent", large_data, %{size: "large"})
      
      Logger.info("Writing large event payload")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [large_event])
      assert {:ok, 0} = result
      
      # Force persistence
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      # Read back and verify
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 1, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 1
      
      recovered_event = Enum.at(read_events, 0)
      assert recovered_event.data.large_text == large_data.large_text
      assert recovered_event.data.large_array == large_data.large_array
      assert recovered_event.data.large_map == large_data.large_map
      assert recovered_event.data.checksum == large_data.checksum
      assert recovered_event.metadata.size == "large"
      
      Logger.info("Successfully verified large payload persistence and recovery")
    end
  end
end
