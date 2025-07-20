defmodule ExESDB.StreamsIntegrationTest do
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.StreamsReader
  alias ExESDB.StreamsHelper
  alias ExESDB.Options
  alias ExESDB.Schema.NewEvent
  
  @test_store_id :test_streams_store
  @test_data_dir "/tmp/test_streams_#{:rand.uniform(1000)}"
  
  setup_all do
    # Configure test environment
    opts = [
      store_id: @test_store_id,
      data_dir: @test_data_dir,
      timeout: 5000,
      db_type: :single,
      pub_sub: :test_pubsub,
      reader_idle_ms: 1000,
      writer_idle_ms: 1000
    ]
    
    Logger.info("Starting ExESDB.System for streams integration tests with opts: #{inspect(opts)}")
    
    # Start the system
    {:ok, system_pid} = System.start_link(opts)
    
    # Wait for system to be ready
    Process.sleep(2000)
    
    on_exit(fn ->
      Logger.info("Stopping ExESDB.System for streams integration tests")
      if Process.alive?(system_pid) do
        GenServer.stop(system_pid, :normal, 5000)
      end
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
  
  describe "streams writing" do
    test "can write a single event to a new stream" do
      stream_id = "test_stream_#{:rand.uniform(1000)}"
      
      event = create_test_event("TestEvent", %{test: "data", number: 42}, %{source: "test"})
      
      Logger.info("Writing single event to stream: #{stream_id}")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [event])
      
      assert {:ok, 0} = result
      Logger.info("Successfully wrote event to stream #{stream_id}, result: #{inspect(result)}")
    end
    
    test "can write multiple events to a new stream" do
      stream_id = "test_stream_multi_#{:rand.uniform(1000)}"
      
      events = [
        create_test_event("Event1", %{value: 1}),
        create_test_event("Event2", %{value: 2}),
        create_test_event("Event3", %{value: 3})
      ]
      
      Logger.info("Writing #{length(events)} events to stream: #{stream_id}")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      
      assert {:ok, 2} = result
      Logger.info("Successfully wrote #{length(events)} events to stream #{stream_id}")
    end
    
    test "can append to an existing stream" do
      stream_id = "test_stream_append_#{:rand.uniform(1000)}"
      
      # First batch
      events1 = [
        create_test_event("InitialEvent", %{step: 1})
      ]
      
      result1 = StreamsWriter.append_events(@test_store_id, stream_id, -1, events1)
      assert {:ok, 0} = result1
      
      # Second batch
      events2 = [
        create_test_event("AppendedEvent", %{step: 2})
      ]
      
      Logger.info("Appending to existing stream: #{stream_id}")
      
      result2 = StreamsWriter.append_events(@test_store_id, stream_id, 0, events2)
      assert {:ok, 1} = result2
      
      Logger.info("Successfully appended to stream #{stream_id}")
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
    
    test "can write events with complex data structures" do
      stream_id = "test_stream_complex_#{:rand.uniform(1000)}"
      
      complex_data = %{
        nested: %{
          array: [1, 2, 3],
          map: %{key: "value"},
          boolean: true,
          nil_value: nil
        },
        timestamp: DateTime.utc_now(),
        binary: <<1, 2, 3, 4>>
      }
      
      complex_metadata = %{
        correlation_id: UUIDv7.generate(),
        causation_id: UUIDv7.generate(),
        created_at: DateTime.utc_now()
      }
      
      complex_event = create_test_event("ComplexEvent", complex_data, complex_metadata)
      
      Logger.info("Writing complex event to stream: #{stream_id}")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [complex_event])
      
      assert {:ok, 0} = result
      Logger.info("Successfully wrote complex event to stream #{stream_id}")
    end
  end
  
  describe "streams reading" do
    test "can read events from a stream" do
      stream_id = "test_stream_read_#{:rand.uniform(1000)}"
      
      # Write test events
      events = [
        create_test_event("Event1", %{value: 1}),
        create_test_event("Event2", %{value: 2}),
        create_test_event("Event3", %{value: 3})
      ]
      
      {:ok, _} = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      
      Logger.info("Reading events from stream: #{stream_id}")
      
      # Read events
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 3
      
      # Verify event structure
      first_event = Enum.at(read_events, 0)
      assert first_event.event_type == "Event1"
      # Verify the pure Elixir term data
      assert first_event.data == %{value: 1}
      
      Logger.info("Successfully read #{length(read_events)} events from stream #{stream_id}")
    end
    
    test "can read events in forward direction" do
      stream_id = "test_stream_forward_#{:rand.uniform(1000)}"
      
      events = Enum.map(1..5, fn i ->
        create_test_event("Event#{i}", %{sequence: i})
      end)
      
      {:ok, _} = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      
      Logger.info("Reading events forward from stream: #{stream_id}")
      
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 5
      
      # Verify order
      sequences = Enum.map(read_events, fn event -> event.data.sequence end)
      assert sequences == [1, 2, 3, 4, 5]
      
      Logger.info("Successfully read events in forward direction from stream #{stream_id}")
    end
    
    test "can read events in backward direction" do
      stream_id = "test_stream_backward_#{:rand.uniform(1000)}"
      
      events = Enum.map(1..5, fn i ->
        create_test_event("Event#{i}", %{sequence: i})
      end)
      
      {:ok, _} = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      
      Logger.info("Reading events backward from stream: #{stream_id}")
      
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 4, 10, :backward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 5
      
      # Verify reverse order
      sequences = Enum.map(read_events, fn event -> event.data.sequence end)
      assert sequences == [5, 4, 3, 2, 1]
      
      Logger.info("Successfully read events in backward direction from stream #{stream_id}")
    end
    
    test "can read partial events from a stream" do
      stream_id = "test_stream_partial_#{:rand.uniform(1000)}"
      
      events = Enum.map(1..10, fn i ->
        create_test_event("Event#{i}", %{sequence: i})
      end)
      
      {:ok, _} = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      
      Logger.info("Reading partial events from stream: #{stream_id}")
      
      # Read only 3 events starting from position 2
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 2, 3, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 3
      
      # Verify we got the right events
      sequences = Enum.map(read_events, fn event -> event.data.sequence end)
      assert sequences == [3, 4, 5]
      
      Logger.info("Successfully read partial events from stream #{stream_id}")
    end
    
    test "handles reading from non-existent stream" do
      stream_id = "non_existent_stream_#{:rand.uniform(1000)}"
      
      Logger.info("Reading from non-existent stream: #{stream_id}")
      
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 0
      
      Logger.info("Successfully handled non-existent stream #{stream_id}")
    end
    
    test "can get current stream version" do
      stream_id = "test_stream_version_#{:rand.uniform(1000)}"
      
      # Initially should be -1 (no events)
      initial_version = StreamsHelper.get_version!(@test_store_id, stream_id)
      assert initial_version == -1
      
      # Write 3 events
      events = Enum.map(1..3, fn i ->
        create_test_event("Event#{i}", %{sequence: i})
      end)
      
      {:ok, _} = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
      
      # Should now be 2 (0-based indexing)
      version = StreamsHelper.get_version!(@test_store_id, stream_id)
      assert version == 2
      
      Logger.info("Stream #{stream_id} version: #{version}")
    end
    
    test "can list all streams" do
      # Write to multiple streams
      streams = Enum.map(1..3, fn i ->
        stream_id = "list_test_stream_#{i}_#{:rand.uniform(1000)}"
        event = create_test_event("Event", %{stream_num: i})
        {:ok, _} = StreamsWriter.append_events(@test_store_id, stream_id, -1, [event])
        stream_id
      end)
      
      Logger.info("Listing all streams")
      
      {:ok, all_streams} = StreamsReader.get_streams(@test_store_id)
      
      # Should contain our test streams
      Enum.each(streams, fn stream_id ->
        assert stream_id in all_streams
      end)
      
      Logger.info("Successfully listed #{length(all_streams)} streams")
    end
  end
  
  describe "streams edge cases" do
    test "handles empty events list" do
      stream_id = "test_stream_empty_#{:rand.uniform(1000)}"
      
      Logger.info("Testing empty events list for stream: #{stream_id}")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [])
      
      # Should handle empty list gracefully
      assert {:ok, -1} = result
      
      Logger.info("Successfully handled empty events list for stream #{stream_id}")
    end
    
    test "handles very large event payloads" do
      stream_id = "test_stream_large_#{:rand.uniform(1000)}"
      
      # Create a large payload
      large_data = %{
        large_text: String.duplicate("x", 10_000),
        large_array: Enum.to_list(1..1000),
        large_map: Map.new(1..100, fn i -> {:"key#{i}", "value#{i}"} end)
      }
      
      event = create_test_event("LargeEvent", large_data)
      
      Logger.info("Writing large event to stream: #{stream_id}")
      
      result = StreamsWriter.append_events(@test_store_id, stream_id, -1, [event])
      
      assert {:ok, 0} = result
      
      # Verify we can read it back
      {:ok, event_stream} = StreamsReader.stream_events(@test_store_id, stream_id, 0, 1, :forward)
      read_events = Enum.to_list(event_stream)
      
      assert length(read_events) == 1
      
      Logger.info("Successfully handled large event for stream #{stream_id}")
    end
    
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
  end
end
