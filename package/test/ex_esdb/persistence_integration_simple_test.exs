defmodule ExESDB.PersistenceIntegrationSimpleTest do
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.StreamsReader
  alias ExESDB.PersistenceWorker
  alias ExESDB.Schema.NewEvent
  
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
    Process.sleep(3000)
    
    on_exit(fn ->
      Logger.info("Stopping ExESDB.System for persistence integration tests")
      if Process.alive?(system_pid) do
        Process.exit(system_pid, :kill)
        Process.sleep(3000)
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
    
    test "persistence worker handles multiple streams" do
      # Create multiple streams
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
      events = Enum.map(1..10, fn i ->
        create_test_event("IntegrityEvent#{i}", %{
          value: i,
          checksum: :crypto.hash(:md5, "#{i}"),
          timestamp: DateTime.utc_now(),
          metadata: %{sequence: i, batch: "integrity_test"}
        })
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 9} = result
      
      # Force persistence
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      # Read all events and verify integrity
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 15, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 10
      
      # Verify each event's integrity
      Enum.each(read_events, fn event ->
        expected_checksum = :crypto.hash(:md5, "#{event.data.value}")
        assert event.data.checksum == expected_checksum
        assert event.data.metadata.sequence == event.data.value
        assert event.data.metadata.batch == "integrity_test"
      end)
      
      Logger.info("Successfully verified data integrity after persistence")
    end
    
    test "handles large event payloads with persistence" do
      stream_id = "test_large_payload_#{:rand.uniform(1000)}"
      
      # Create a large event payload
      large_data = %{
        large_text: String.duplicate("X", 10_000),
        large_array: Enum.to_list(1..1000),
        large_map: Map.new(1..100, fn i -> {:"key#{i}", "value#{i}"} end),
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
  
  describe "concurrent operations" do
    test "handles concurrent writes to same stream" do
      stream_id = "test_stream_concurrent_#{:rand.uniform(1000)}"
      
      Logger.info("Testing concurrent writes to stream: #{stream_id}")
      
      # Start multiple concurrent writes
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          event = create_test_event("ConcurrentEvent#{i}", %{task_id: i})
          StreamsWriter.append_events(@test_store_id, stream_id, -1, [event])
        end)
      end)
      
      # Wait for all tasks
      results = Enum.map(tasks, &Task.await/1)
      
      # At least one should succeed
      successful_results = Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      assert length(successful_results) >= 1
      
      Logger.info("Concurrent writes test completed for stream #{stream_id}")
    end
    
    test "handles concurrent persistence requests" do
      stream_id = "test_concurrent_persistence_#{:rand.uniform(1000)}"
      
      # Write some events
      events = Enum.map(1..3, fn i ->
        create_test_event("Event#{i}", %{value: i})
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 2} = result
      
      # Start multiple concurrent persistence requests
      tasks = Enum.map(1..5, fn _i ->
        Task.async(fn ->
          PersistenceWorker.request_persistence(@test_store_id)
        end)
      end)
      
      # Wait for all tasks
      results = Enum.map(tasks, &Task.await/1)
      
      # All should succeed
      Enum.each(results, fn result ->
        assert result == :ok
      end)
      
      # Force persistence to ensure everything is persisted
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      Logger.info("Successfully verified concurrent persistence requests")
    end
  end
  
  describe "edge cases" do
    test "handles empty events list" do
      stream_id = "test_stream_empty_#{:rand.uniform(1000)}"
      
      Logger.info("Testing empty events list for stream: #{stream_id}")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [])
      
      # Should handle empty list gracefully
      assert {:ok, -1} = result
      
      Logger.info("Successfully handled empty events list for stream #{stream_id}")
    end
    
    test "handles version conflicts correctly" do
      stream_id = "test_stream_conflict_#{:rand.uniform(1000)}"
      
      # Write initial event
      event1 = create_test_event("Event1", %{value: 1})
      result1 = StreamsWriter.append_events(@test_store_id, stream_id, -1, [event1])
      assert {:ok, 0} = result1
      
      # Try to write with wrong expected version
      event2 = create_test_event("Event2", %{value: 2})
      result2 = StreamsWriter.append_events(@test_store_id, stream_id, 5, [event2])
      
      Logger.info("Testing version conflict for stream: #{stream_id}")
      
      # Should fail due to version mismatch
      assert {:error, _reason} = result2
      Logger.info("Version conflict handled correctly for stream #{stream_id}")
    end
    
    test "handles persistence requests after force persistence" do
      stream_id = "test_persistence_after_force_#{:rand.uniform(1000)}"
      
      # Write some events
      events = Enum.map(1..3, fn i ->
        create_test_event("Event#{i}", %{value: i})
      end)
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      assert {:ok, 2} = result
      
      # Force persistence
      force_result = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result == :ok
      
      # Request persistence again - should still work
      request_result = PersistenceWorker.request_persistence(@test_store_id)
      assert request_result == :ok
      
      # Force persistence again - should still work
      force_result2 = PersistenceWorker.force_persistence(@test_store_id)
      assert force_result2 == :ok
      
      Logger.info("Successfully verified persistence requests after force persistence")
    end
  end
end
