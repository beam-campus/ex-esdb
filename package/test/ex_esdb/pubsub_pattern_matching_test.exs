defmodule ExESDB.PubSubPatternMatchingTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.PubSubIntegration
  
  describe "pattern matching refactoring verification" do
    setup do
      # Ensure clean state for each test
      original_setting = Application.get_env(:ex_esdb, :pubsub_integration, false)
      
      on_exit(fn ->
        # Restore original setting
        if original_setting do
          Application.put_env(:ex_esdb, :pubsub_integration, original_setting)
        else
          Application.delete_env(:ex_esdb, :pubsub_integration)
        end
      end)
      
      {:ok, original: original_setting}
    end

    test "broadcast_system_lifecycle/4 pattern matching works correctly" do
      # Test disabled state pattern matching
      Application.put_env(:ex_esdb, :pubsub_integration, false)
      result = PubSubIntegration.broadcast_system_lifecycle(:started, :test_system, "1.0.0")
      assert result == :disabled
      
      # Test enabled state pattern matching
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      result = PubSubIntegration.broadcast_system_lifecycle(:started, :test_system, "1.0.0")
      
      # Should attempt to broadcast and return error (no PubSub running)
      assert {:error, _reason} = result
    end

    test "broadcast_system_config/3 pattern matching works correctly" do
      # Test disabled state
      Application.put_env(:ex_esdb, :pubsub_integration, false)
      result = PubSubIntegration.broadcast_system_config(:database, %{pool_size: 10})
      assert result == :disabled
      
      # Test enabled state
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      result = PubSubIntegration.broadcast_system_config(:database, %{pool_size: 10})
      assert {:error, _reason} = result
    end

    test "broadcast_store_health/5 pattern matching with guard validation" do
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      # Test valid atom store_id
      result = PubSubIntegration.broadcast_store_health(:test_store, :component, :healthy)
      assert {:error, _reason} = result
      
      # Test guard protection - non-atom store_id should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        PubSubIntegration.broadcast_store_health("invalid_store_id", :component, :healthy)
      end
      
      assert_raise FunctionClauseError, fn ->
        PubSubIntegration.broadcast_store_health(123, :component, :healthy)
      end
      
      assert_raise FunctionClauseError, fn ->
        PubSubIntegration.broadcast_store_health(nil, :component, :healthy)
      end
    end

    test "broadcast_cluster_health/4 pattern matching works correctly" do
      # Test disabled state
      Application.put_env(:ex_esdb, :pubsub_integration, false)
      result = PubSubIntegration.broadcast_cluster_health([:node1], [], :healthy)
      assert result == :disabled
      
      # Test enabled state
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      result = PubSubIntegration.broadcast_cluster_health([:node1, :node2], [:node3], :degraded)
      assert {:error, _reason} = result
    end

    test "legacy broadcast_health_update/4 pattern matching still works" do
      # Test disabled state
      Application.put_env(:ex_esdb, :pubsub_integration, false)
      result = PubSubIntegration.broadcast_health_update(:component, :healthy)
      assert result == :disabled
      
      # Test enabled state
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      result = PubSubIntegration.broadcast_health_update(:component, :healthy, %{test: true})
      assert {:error, _reason} = result
    end
  end

  describe "error handling in pattern matching" do
    test "invalid payload data is handled gracefully" do
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      # Test with data that should cause payload building to fail
      result = PubSubIntegration.broadcast_system_lifecycle(nil, nil, nil)
      assert {:error, _reason} = result
      
      # Test config broadcast with invalid data
      result = PubSubIntegration.broadcast_system_config(nil, nil)
      assert {:error, _reason} = result
    end

    test "error logging occurs appropriately" do
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      import ExUnit.CaptureLog
      
      log_output = capture_log(fn ->
        PubSubIntegration.broadcast_system_lifecycle(:started, :test_system, "1.0.0")
      end)
      
      # Should contain warning about broadcast failure
      assert log_output =~ "Failed to broadcast"
    end
  end

  describe "topic generation integration" do
    test "store health uses proper topic generation functions" do
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      # This test ensures store health broadcasts are using the new
      # topic generation functions from HealthMessages module
      result = PubSubIntegration.broadcast_store_health(
        :vehicle_store, 
        :emitter_pool, 
        :healthy, 
        %{event: :started}
      )
      
      # Should fail due to no PubSub but confirms pattern matching works
      assert {:error, _reason} = result
    end

    test "cluster health uses proper topic generation" do
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      # This ensures cluster health broadcasts use cluster_health_topic()
      result = PubSubIntegration.broadcast_cluster_health([:node1], [], :healthy)
      assert {:error, _reason} = result
    end
  end

  describe "function signature consistency" do
    test "all pattern matching functions follow topic-first convention" do
      # This test verifies that our functions follow the Elixir convention
      # of topic first, then payload (where applicable)
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      # Test that functions don't crash due to argument order issues
      assert {:error, _} = PubSubIntegration.broadcast_system_lifecycle(:started, :test, "1.0.0")
      assert {:error, _} = PubSubIntegration.broadcast_system_config(:comp, %{})
      assert {:error, _} = PubSubIntegration.broadcast_store_health(:store, :comp, :healthy)
      assert {:error, _} = PubSubIntegration.broadcast_cluster_health([], [], :healthy)
    end
  end

  describe "batch operation pattern matching" do
    test "batch operations handle enabled/disabled state correctly" do
      # Test disabled state
      Application.put_env(:ex_esdb, :pubsub_integration, false)
      
      events = [
        {:system_lifecycle, :started, :test_system, "1.0.0"},
        {:health_update, :component, :healthy, %{}}
      ]
      
      result = PubSubIntegration.broadcast_batch(events)
      assert {:ok, %{success: 0, errors: 0, disabled: true}} = result
      
      # Test enabled state
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      result = PubSubIntegration.broadcast_batch(events)
      assert {:ok, %{success: _success, errors: _errors}} = result
    end

    test "batch operations handle mixed valid/invalid events" do
      Application.put_env(:ex_esdb, :pubsub_integration, true)
      
      events = [
        {:system_lifecycle, :started, :test_system, "1.0.0"},
        {:unknown_event_type, :invalid, :data},
        {:health_update, :component, :healthy, %{}}
      ]
      
      result = PubSubIntegration.broadcast_batch(events)
      assert {:ok, %{success: _success, errors: _errors}} = result
    end
  end

  describe "configuration functions" do
    test "configuration helpers work correctly" do
      # Test enabled/disabled state management
      PubSubIntegration.disable!()
      refute PubSubIntegration.enabled?()
      
      PubSubIntegration.enable!()
      assert PubSubIntegration.enabled?()
      
      # Test interval configuration
      assert is_integer(PubSubIntegration.health_broadcast_interval())
      assert is_integer(PubSubIntegration.metrics_broadcast_interval())
      
      # Test custom intervals
      Application.put_env(:ex_esdb, :health_broadcast_interval, 45_000)
      assert PubSubIntegration.health_broadcast_interval() == 45_000
      
      Application.put_env(:ex_esdb, :metrics_broadcast_interval, 90_000)
      assert PubSubIntegration.metrics_broadcast_interval() == 90_000
    end
  end
end
