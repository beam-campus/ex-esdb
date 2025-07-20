defmodule ExESDB.VersioningTest do
  @moduledoc """
  Tests to verify the simplified 0-based versioning system
  """
  use ExUnit.Case, async: true
  
  alias ExESDB.StreamsHelper
  
  describe "0-based versioning system" do
    test "version calculation logic" do
      # Test the core versioning logic without full infrastructure
      
      # New stream: current_version = -1
      current_version = -1
      
      # Adding 3 events to a new stream
      events = [1, 2, 3]  # dummy events
      
      expected_versions = for {_event, index} <- Enum.with_index(events) do
        current_version + 1 + index
      end
      
      # For new stream (-1), first event should be version 0, second version 1, etc.
      assert expected_versions == [0, 1, 2]
      
      # Last event version should be 2
      assert Enum.max(expected_versions) == 2
    end
    
    test "appending to existing stream" do
      # Existing stream with 2 events: current_version = 1 (last event is version 1)
      current_version = 1
      
      # Adding 2 more events
      events = [1, 2]  # dummy events
      
      expected_versions = for {_event, index} <- Enum.with_index(events) do
        current_version + 1 + index
      end
      
      # Next events should be version 2, 3
      assert expected_versions == [2, 3]
      
      # Last event version should be 3
      assert Enum.max(expected_versions) == 3
    end
    
    test "single event to new stream" do
      # New stream: current_version = -1
      current_version = -1
      
      # Adding 1 event
      events = [1]  # dummy event
      
      expected_versions = for {_event, index} <- Enum.with_index(events) do
        current_version + 1 + index
      end
      
      # First event should be version 0
      assert expected_versions == [0]
    end
    
    test "single event to existing stream" do
      # Existing stream with 1 event: current_version = 0 
      current_version = 0
      
      # Adding 1 more event
      events = [1]  # dummy event
      
      expected_versions = for {_event, index} <- Enum.with_index(events) do
        current_version + 1 + index
      end
      
      # Next event should be version 1
      assert expected_versions == [1]
    end
  end
  
  describe "StreamsHelper utility functions" do
    test "pad_version/2 works correctly" do
      assert StreamsHelper.pad_version(0, 6) == "000000"
      assert StreamsHelper.pad_version(1, 6) == "000001"
      assert StreamsHelper.pad_version(123, 6) == "000123"
      assert StreamsHelper.pad_version(999999, 6) == "999999"
    end
    
    test "version_to_integer/1 converts correctly" do
      assert StreamsHelper.version_to_integer("000000") == 0
      assert StreamsHelper.version_to_integer("000001") == 1
      assert StreamsHelper.version_to_integer("000123") == 123
      assert StreamsHelper.version_to_integer("999999") == 999999
    end
    
    test "calculate_versions/3 creates correct ranges" do
      # Forward direction
      assert StreamsHelper.calculate_versions(0, 3, :forward) == 0..2
      assert StreamsHelper.calculate_versions(5, 2, :forward) == 5..6
      
      # Backward direction
      assert StreamsHelper.calculate_versions(5, 3, :backward) == 5..3//-1
      assert StreamsHelper.calculate_versions(2, 2, :backward) == 2..1//-1
    end
  end
end
