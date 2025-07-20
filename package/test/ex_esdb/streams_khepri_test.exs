defmodule ExESDB.StreamsKhepriTest do
  use ExUnit.Case
  doctest ExESDB.StreamsReader
  doctest ExESDB.StreamsWriter

  alias ExESDB.StreamsReader
  alias ExESDB.StreamsWriter
  alias ExESDB.StreamsHelper
  alias ExESDB.Schema.NewEvent
  alias ExESDB.Schema.EventRecord
  alias ExESDB.Options, as: Options

  require Logger

  @test_store :test_khepri_store
  @test_stream "test_stream"
  @test_stream_2 "test_stream_2"

  setup do
    # Clean up any existing data
    data_dir = "tmp/khepri_test_store"
    File.rm_rf!(data_dir)
    
    # Start the test store
    opts = [
      data_dir: data_dir,
      store_id: @test_store,
      timeout: 1_000,
      db_type: :single,
      pub_sub: :khepri_test_pub_sub
    ]
    
    # Start khepri for the test store
    {:ok, _} = :khepri.start(@test_store, [data_dir: data_dir])
    
    on_exit(fn ->
      # Clean up
      try do
        :khepri.stop(@test_store)
      rescue
        _ -> :ok
      end
      File.rm_rf!(data_dir)
    end)

    %{opts: opts, store: @test_store}
  end

  describe "StreamsHelper operations" do
    test "stream_exists?/2 returns false for non-existent stream", %{store: store} do
      refute StreamsHelper.stream_exists?(store, "non_existent_stream")
    end

    test "get_version!/2 returns -1 for non-existent stream", %{store: store} do
      assert StreamsHelper.get_version!(store, "non_existent_stream") == -1
    end

    test "pad_version/2 pads version numbers correctly" do
      assert StreamsHelper.pad_version(0, 6) == "000000"
      assert StreamsHelper.pad_version(1, 6) == "000001"
      assert StreamsHelper.pad_version(123, 6) == "000123"
      assert StreamsHelper.pad_version(999999, 6) == "999999"
    end

    test "version_to_integer/1 converts padded versions back to integers" do
      assert StreamsHelper.version_to_integer("000000") == 0
      assert StreamsHelper.version_to_integer("000001") == 1
      assert StreamsHelper.version_to_integer("000123") == 123
      assert StreamsHelper.version_to_integer("999999") == 999999
    end

    test "calculate_versions/3 creates correct version ranges" do
      # Forward direction
      assert StreamsHelper.calculate_versions(0, 3, :forward) == 0..2
      assert StreamsHelper.calculate_versions(5, 2, :forward) == 5..6
      
      # Backward direction
      assert StreamsHelper.calculate_versions(5, 3, :backward) == 5..3
      assert StreamsHelper.calculate_versions(2, 2, :backward) == 2..1
    end
  end

  describe "Basic Khepri operations" do
    test "can store and retrieve data directly in khepri", %{store: store} do
      # Test basic khepri operations
      key = [:test, :direct]
      value = %{data: "test_value", timestamp: System.system_time()}
      
      # Store data
      assert :ok = :khepri.put(store, key, value)
      
      # Retrieve data
      assert {:ok, ^value} = :khepri.get(store, key)
      
      # Check if key exists
      assert :khepri.exists(store, key)
    end

    test "can store events in stream structure", %{store: store} do
      stream_id = "direct_test_stream"
      padded_version = StreamsHelper.pad_version(0, 6)
      
      event_data = %EventRecord{
        event_stream_id: stream_id,
        event_number: 0,
        event_id: UUID.uuid4(:binary),
        event_type: "TestEvent",
        data_content_type: 1,
        metadata_content_type: 1,
        data: "test event data",
        metadata: "test metadata",
        created: System.system_time(),
        created_epoch: System.system_time(:microsecond)
      }
      
      # Store event
      assert :ok = :khepri.put(store, [:streams, stream_id, padded_version], event_data)
      
      # Retrieve event
      assert {:ok, ^event_data} = :khepri.get(store, [:streams, stream_id, padded_version])
      
      # Check stream exists
      assert StreamsHelper.stream_exists?(store, stream_id)
      
      # Check version
      assert StreamsHelper.get_version!(store, stream_id) == 0
    end
  end

  describe "StreamsWriter operations" do
    test "can append events to a new stream", %{store: store} do
      events = [
        create_test_event("TestEvent1", "data1"),
        create_test_event("TestEvent2", "data2")
      ]
      
      # Append events to a new stream (expected version -1)
      assert {:ok, final_version} = StreamsWriter.append_events(store, @test_stream, -1, events)
      
      # Should return the version of the last event (0-based indexing)
      assert final_version == 1
      
      # Check stream exists
      assert StreamsHelper.stream_exists?(store, @test_stream)
      
      # Check version
      assert StreamsHelper.get_version!(store, @test_stream) == 1
    end

    test "can append events to an existing stream", %{store: store} do
      # First, create a stream with one event
      event1 = [create_test_event("TestEvent1", "data1")]
      assert {:ok, 0} = StreamsWriter.append_events(store, @test_stream, -1, event1)
      
      # Then append more events
      events2 = [
        create_test_event("TestEvent2", "data2"),
        create_test_event("TestEvent3", "data3")
      ]
      assert {:ok, final_version} = StreamsWriter.append_events(store, @test_stream, 0, events2)
      
      # Should return the version of the last event
      assert final_version == 2
      
      # Check version
      assert StreamsHelper.get_version!(store, @test_stream) == 2
    end

    test "returns error when expected version is incorrect", %{store: store} do
      # Try to append to a new stream with wrong expected version
      events = [create_test_event("TestEvent", "data")]
      
      assert {:error, :wrong_expected_version} = 
        StreamsWriter.append_events(store, @test_stream, 0, events)
      
      # Create a stream first
      assert {:ok, 0} = StreamsWriter.append_events(store, @test_stream, -1, events)
      
      # Try to append with wrong expected version
      assert {:error, :wrong_expected_version} = 
        StreamsWriter.append_events(store, @test_stream, 5, events)
    end

    test "handles multiple streams independently", %{store: store} do
      events1 = [create_test_event("Stream1Event", "data1")]
      events2 = [create_test_event("Stream2Event", "data2")]
      
      # Append to different streams
      assert {:ok, 0} = StreamsWriter.append_events(store, @test_stream, -1, events1)
      assert {:ok, 0} = StreamsWriter.append_events(store, @test_stream_2, -1, events2)
      
      # Check both streams exist with correct versions
      assert StreamsHelper.get_version!(store, @test_stream) == 0
      assert StreamsHelper.get_version!(store, @test_stream_2) == 0
    end
  end

  describe "StreamsReader operations" do
    setup %{store: store} do
      # Create a test stream with multiple events
      events = [
        create_test_event("Event1", "data1"),
        create_test_event("Event2", "data2"),
        create_test_event("Event3", "data3"),
        create_test_event("Event4", "data4"),
        create_test_event("Event5", "data5")
      ]
      
      {:ok, _} = StreamsWriter.append_events(store, @test_stream, -1, events)
      
      %{events: events}
    end

    test "can read events from a stream forward", %{store: store} do
      # Read events from the beginning
      assert {:ok, stream} = StreamsReader.stream_events(store, @test_stream, 0, 3, :forward)
      
      events = Enum.to_list(stream)
      assert length(events) == 3
      
      # Check event order and content
      assert Enum.at(events, 0).event_number == 0
      assert Enum.at(events, 1).event_number == 1
      assert Enum.at(events, 2).event_number == 2
      
      assert Enum.at(events, 0).event_type == "Event1"
      assert Enum.at(events, 1).event_type == "Event2"
      assert Enum.at(events, 2).event_type == "Event3"
    end

    test "can read events from a stream backward", %{store: store} do
      # Read events from the end
      assert {:ok, stream} = StreamsReader.stream_events(store, @test_stream, 4, 3, :backward)
      
      events = Enum.to_list(stream)
      assert length(events) == 3
      
      # Check event order (should be in reverse)
      assert Enum.at(events, 0).event_number == 4
      assert Enum.at(events, 1).event_number == 3
      assert Enum.at(events, 2).event_number == 2
      
      assert Enum.at(events, 0).event_type == "Event5"
      assert Enum.at(events, 1).event_type == "Event4"
      assert Enum.at(events, 2).event_type == "Event3"
    end

    test "can read partial events from stream", %{store: store} do
      # Read events from the middle
      assert {:ok, stream} = StreamsReader.stream_events(store, @test_stream, 2, 2, :forward)
      
      events = Enum.to_list(stream)
      assert length(events) == 2
      
      assert Enum.at(events, 0).event_number == 2
      assert Enum.at(events, 1).event_number == 3
    end

    test "returns empty stream when reading beyond stream end", %{store: store} do
      assert {:ok, stream} = StreamsReader.stream_events(store, @test_stream, 10, 5, :forward)
      
      events = Enum.to_list(stream)
      assert length(events) == 0
    end

    test "returns empty stream for non-existent stream", %{store: store} do
      assert {:ok, stream} = StreamsReader.stream_events(store, "non_existent", 0, 5, :forward)
      
      events = Enum.to_list(stream)
      assert length(events) == 0
    end

    test "can get list of all streams", %{store: store} do
      # Create multiple streams
      {:ok, _} = StreamsWriter.append_events(store, @test_stream_2, -1, [create_test_event("Test", "data")])
      {:ok, _} = StreamsWriter.append_events(store, "stream3", -1, [create_test_event("Test", "data")])
      
      # Get streams
      assert {:ok, streams} = StreamsReader.get_streams(store)
      
      # Should contain all created streams
      assert @test_stream in streams
      assert @test_stream_2 in streams
      assert "stream3" in streams
      
      # Should be at least 3 streams
      assert length(streams) >= 3
    end

    test "handles invalid parameters gracefully", %{store: store} do
      # Invalid start version
      assert {:error, :invalid_start_version} = 
        StreamsReader.stream_events(store, @test_stream, -1, 5, :forward)
      
      # Invalid count
      assert {:error, :invalid_count} = 
        StreamsReader.stream_events(store, @test_stream, 0, 0, :forward)
      
      assert {:error, :invalid_count} = 
        StreamsReader.stream_events(store, @test_stream, 0, -1, :forward)
    end
  end

  describe "End-to-end stream operations" do
    test "complete write and read cycle", %{store: store} do
      # Create test data
      test_events = [
        create_test_event("UserRegistered", %{user_id: 123, email: "test@example.com"}),
        create_test_event("UserActivated", %{user_id: 123, activated_at: "2023-01-01"}),
        create_test_event("UserProfileUpdated", %{user_id: 123, name: "John Doe"})
      ]
      
      stream_id = "user-123"
      
      # Write events
      assert {:ok, 2} = StreamsWriter.append_events(store, stream_id, -1, test_events)
      
      # Verify stream exists and has correct version
      assert StreamsHelper.stream_exists?(store, stream_id)
      assert StreamsHelper.get_version!(store, stream_id) == 2
      
      # Read all events
      assert {:ok, stream} = StreamsReader.stream_events(store, stream_id, 0, 10, :forward)
      read_events = Enum.to_list(stream)
      
      # Verify all events were read correctly
      assert length(read_events) == 3
      
      # Verify event content
      assert Enum.at(read_events, 0).event_type == "UserRegistered"
      assert Enum.at(read_events, 1).event_type == "UserActivated"
      assert Enum.at(read_events, 2).event_type == "UserProfileUpdated"
      
      # Verify event order
      assert Enum.at(read_events, 0).event_number == 0
      assert Enum.at(read_events, 1).event_number == 1
      assert Enum.at(read_events, 2).event_number == 2
      
      # Verify stream ID is correct
      assert Enum.all?(read_events, fn event -> event.event_stream_id == stream_id end)
      
      # Verify timestamps are set
      assert Enum.all?(read_events, fn event -> 
        event.created != nil and event.created_epoch != nil
      end)
    end

    test "concurrent writes to different streams", %{store: store} do
      # Create multiple tasks that write to different streams
      tasks = for i <- 1..5 do
        Task.async(fn ->
          stream_id = "concurrent-stream-#{i}"
          events = [
            create_test_event("Event1", "data#{i}-1"),
            create_test_event("Event2", "data#{i}-2")
          ]
          
          {:ok, version} = StreamsWriter.append_events(store, stream_id, -1, events)
          {stream_id, version}
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)
      
      # Verify all streams were created successfully
      assert length(results) == 5
      
      for {stream_id, version} <- results do
        assert version == 1  # Last event should be at version 1
        assert StreamsHelper.stream_exists?(store, stream_id)
        assert StreamsHelper.get_version!(store, stream_id) == 1
      end
      
      # Verify we can read from all streams
      for {stream_id, _} <- results do
        assert {:ok, stream} = StreamsReader.stream_events(store, stream_id, 0, 10, :forward)
        events = Enum.to_list(stream)
        assert length(events) == 2
      end
    end

    test "large stream with many events", %{store: store} do
      # Create a large number of events
      event_count = 100
      events = for i <- 1..event_count do
        create_test_event("Event#{i}", "data for event #{i}")
      end
      
      stream_id = "large-stream"
      
      # Write all events in one go
      assert {:ok, final_version} = StreamsWriter.append_events(store, stream_id, -1, events)
      assert final_version == event_count - 1
      
      # Verify stream version
      assert StreamsHelper.get_version!(store, stream_id) == event_count - 1
      
      # Read events in chunks
      chunk_size = 10
      all_read_events = []
      
      for start_pos <- 0..(event_count - 1)//chunk_size do
        assert {:ok, stream} = StreamsReader.stream_events(store, stream_id, start_pos, chunk_size, :forward)
        chunk_events = Enum.to_list(stream)
        all_read_events = all_read_events ++ chunk_events
      end
      
      # Verify we read all events
      assert length(all_read_events) == event_count
      
      # Verify event order
      for {event, index} <- Enum.with_index(all_read_events) do
        assert event.event_number == index
        assert event.event_type == "Event#{index + 1}"
      end
    end
  end

  describe "Error handling and edge cases" do
    test "handles khepri errors gracefully", %{store: store} do
      # Try to read from a store that doesn't exist
      non_existent_store = :non_existent_store
      
      # This should handle the error gracefully
      assert {:error, _} = StreamsReader.stream_events(non_existent_store, "test", 0, 5, :forward)
    end

    test "handles malformed event data", %{store: store} do
      # Create a malformed event (missing required fields)
      malformed_event = %NewEvent{
        event_id: UUID.uuid4(:binary),
        event_type: "MalformedEvent",
        # Missing required fields
        data_content_type: 1,
        metadata_content_type: 1,
        data: "test data"
      }
      
      # This should either succeed or fail gracefully
      result = StreamsWriter.append_events(store, "malformed-stream", -1, [malformed_event])
      
      case result do
        {:ok, _} -> 
          # If it succeeds, we should be able to read it back
          assert {:ok, stream} = StreamsReader.stream_events(store, "malformed-stream", 0, 1, :forward)
          events = Enum.to_list(stream)
          assert length(events) == 1
          
        {:error, reason} ->
          # If it fails, it should be a meaningful error
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end

  # Helper functions
  defp create_test_event(event_type, data) do
    %NewEvent{
      event_id: UUID.uuid4(:binary),
      event_type: event_type,
      data_content_type: 0,  # Pure Erlang/Elixir terms
      metadata_content_type: 0,  # Pure Erlang/Elixir terms
      data: data,
      metadata: "test metadata"
    }
  end
end
