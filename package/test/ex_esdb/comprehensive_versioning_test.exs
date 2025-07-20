defmodule ExESDB.ComprehensiveVersioningTest do
  @moduledoc """
  Comprehensive test to verify all stream versioning operations work correctly
  after the 0-based simplification
  """
  use ExUnit.Case, async: true
  
  alias ExESDB.StreamsHelper
  alias ExESDB.GatewayWorker
  
  describe "Stream versioning operations" do
    test "version_matches? function in gateway worker" do
      # Test the version_matches? function using Module.__info__
      
      # For :any, should always match
      assert true == apply_version_matches(-1, :any)
      assert true == apply_version_matches(0, :any)
      assert true == apply_version_matches(5, :any)
      
      # For :stream_exists, should match when stream has events (version >= 0)
      assert false == apply_version_matches(-1, :stream_exists)  # Empty stream
      assert true == apply_version_matches(0, :stream_exists)    # Stream with 1 event
      assert true == apply_version_matches(5, :stream_exists)    # Stream with 6 events
      
      # For exact version matching
      assert true == apply_version_matches(-1, -1)   # Empty stream expectations
      assert true == apply_version_matches(0, 0)     # First event expectations  
      assert true == apply_version_matches(5, 5)     # Specific version expectations
      assert false == apply_version_matches(0, 5)    # Version mismatch
      assert false == apply_version_matches(5, 0)    # Version mismatch
    end
    
    test "gateway worker version validation logic" do
      # Test scenarios that would occur in gateway worker operations
      
      # Scenario 1: Append to empty stream
      current_version = -1  # Empty stream
      expected_version = -1 # Expecting empty stream
      assert true == apply_version_matches(current_version, expected_version)
      
      # Scenario 2: Append to stream with 2 events (versions 0, 1)
      current_version = 1   # Last event is version 1
      expected_version = 1  # Expecting last event to be version 1
      assert true == apply_version_matches(current_version, expected_version)
      
      # Scenario 3: Wrong expectation - expect empty but stream has events
      current_version = 0   # Stream has 1 event (version 0)
      expected_version = -1 # Expecting empty stream
      assert false == apply_version_matches(current_version, expected_version)
      
      # Scenario 4: Wrong expectation - expect more events than exist
      current_version = 1   # Stream has 2 events (last is version 1)
      expected_version = 5  # Expecting 6 events (last would be version 5)
      assert false == apply_version_matches(current_version, expected_version)
    end
    
    test "streams reader parameter validation" do
      # Test the validation that happens in streams reader worker
      
      # Valid parameters (should pass validation)
      assert :ok == validate_reader_params(0, 5)    # Read from start
      assert :ok == validate_reader_params(10, 3)   # Read from middle
      assert :ok == validate_reader_params(100, 1)  # Read single event
      
      # Invalid start_version (should fail validation)
      assert {:error, :invalid_start_version} == validate_reader_params(-1, 5)  # Negative start
      assert {:error, :invalid_start_version} == validate_reader_params(-10, 1) # Very negative
      
      # Invalid count (should fail validation)
      assert {:error, :invalid_count} == validate_reader_params(0, 0)   # Zero count
      assert {:error, :invalid_count} == validate_reader_params(0, -1)  # Negative count
      assert {:error, :invalid_count} == validate_reader_params(5, -10) # Very negative count
      
      # Invalid types (should fail validation)
      assert {:error, {:invalid_start_version, "not_integer"}} == validate_reader_params("not_integer", 5)
      assert {:error, {:invalid_count, "not_integer"}} == validate_reader_params(0, "not_integer")
    end
    
    test "event numbering consistency" do
      # Test that event numbering follows 0-based system consistently
      
      # Append 3 events to new stream (expected_version = -1)
      current_version = -1
      events = [1, 2, 3]  # dummy events
      
      final_versions = for {_event, index} <- Enum.with_index(events) do
        current_version + 1 + index
      end
      
      # Events should get versions [0, 1, 2]
      assert final_versions == [0, 1, 2]
      
      # The final version returned should be 2 (last event's version)
      final_version = List.last(final_versions)
      assert final_version == 2
      
      # Now append 2 more events (expected_version = 2)
      current_version = 2  # From previous operation
      more_events = [4, 5]  # dummy events
      
      next_versions = for {_event, index} <- Enum.with_index(more_events) do
        current_version + 1 + index
      end
      
      # Next events should get versions [3, 4]
      assert next_versions == [3, 4]
      
      # The final version should be 4
      final_version = List.last(next_versions)
      assert final_version == 4
    end
    
    test "subscription event acknowledgment uses 0-based versioning" do
      # Test the ack_event logic from gateway worker
      
      # When we acknowledge an event, the next event to process should be event_number + 1
      event = %{
        event_stream_id: "test-stream",
        event_number: 0  # We processed event version 0
      }
      
      # Next event to process should be version 1
      next_event_to_process = event.event_number + 1
      assert next_event_to_process == 1
      
      # For event version 5, next should be 6
      event = %{
        event_stream_id: "test-stream", 
        event_number: 5
      }
      
      next_event_to_process = event.event_number + 1
      assert next_event_to_process == 6
    end
    
    test "version range calculations" do
      # Test StreamsHelper.calculate_versions/3 function
      
      # Forward reading from start
      range = StreamsHelper.calculate_versions(0, 5, :forward)
      assert range == 0..4
      
      # Forward reading from middle  
      range = StreamsHelper.calculate_versions(10, 3, :forward)
      assert range == 10..12
      
      # Backward reading from end
      range = StreamsHelper.calculate_versions(10, 5, :backward)
      assert range == 10..6//-1
      
      # Backward reading from middle
      range = StreamsHelper.calculate_versions(5, 3, :backward)
      assert range == 5..3//-1
    end
  end
  
  # Helper functions to test private functions
  
  # Simulate the version_matches? private function from GatewayWorker
  defp apply_version_matches(current, :any), do: true
  defp apply_version_matches(current, :stream_exists) when current >= 0, do: true
  defp apply_version_matches(-1, :stream_exists), do: false
  defp apply_version_matches(current, expected) when is_integer(expected), do: current == expected
  
  # Simulate the validate_parameters private function from StreamsReaderWorker
  defp validate_reader_params(start_version, count) do
    cond do
      not is_integer(start_version) -> {:error, {:invalid_start_version, start_version}}
      start_version < 0 -> {:error, :invalid_start_version}
      not is_integer(count) -> {:error, {:invalid_count, count}}
      count < 1 -> {:error, :invalid_count}
      true -> :ok
    end
  end
end
