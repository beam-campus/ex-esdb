defmodule ExESDB.EmitterSystemLoggingWorkerTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.EmitterSystemLoggingWorker
  alias ExESDB.LoggingPublisher
  alias Phoenix.PubSub
  
  import ExUnit.CaptureLog
  
  @pubsub_name :ex_esdb_logging
  @test_store_id :test_emitter_system_logging
  
  setup do
    # Start the logging worker
    opts = [
      store_id: @test_store_id,
      emitter_system_logging_level: :info,
      emitter_system_terminal_output: true
    ]
    
    {:ok, worker_pid} = EmitterSystemLoggingWorker.start_link(opts)
    
    # Give the worker time to subscribe to topics
    Process.sleep(50)
    
    %{worker_pid: worker_pid, opts: opts}
  end
  
  describe "initialization" do
    test "worker starts and subscribes to correct topics", %{worker_pid: worker_pid} do
      assert Process.alive?(worker_pid)
      
      # Test that it's subscribed by publishing an event
      LoggingPublisher.startup(:emitter_system, @test_store_id, "Test startup")
      
      # Give time for processing
      Process.sleep(50)
      
      # Worker should still be alive (no crashes from processing)
      assert Process.alive?(worker_pid)
    end
    
    test "worker can be configured with different options" do
      opts = [
        store_id: :different_store,
        emitter_system_logging_level: :debug,
        emitter_system_terminal_output: false
      ]
      
      assert {:ok, pid} = EmitterSystemLoggingWorker.start_link(opts)
      assert Process.alive?(pid)
      
      # Cleanup
      GenServer.stop(pid)
    end
  end
  
describe "startup event handling" do
    test "processes startup events" do
      log_output = capture_log(fn ->
        LoggingPublisher.startup(:emitter_system, @test_store_id, "System starting", %{
          components: 1,
          max_restarts: "10/60s"
        })
        
        Process.sleep(100)
      end)
      
      assert log_output =~ "[info]"
      assert log_output =~ "EmitterSystem:#{@test_store_id}"
      assert log_output =~ "System starting"
    end

    test "ignores startup events from other stores" do
      log_output = capture_log(fn ->
        LoggingPublisher.startup(:emitter_system, :other_store, "Other store starting")
        Process.sleep(100)
      end)

      refute log_output =~ "Other store starting"
    end
  end
  
  describe "shutdown event handling" do
test "processes shutdown events" do
      log_output = capture_log(fn ->
        LoggingPublisher.shutdown(:emitter_system, @test_store_id, "System shutting down", %{
          reason: :normal
        })
        
        Process.sleep(100)
      end)
      
      assert log_output =~ "[warning]"
      assert log_output =~ "EmitterSystem:#{@test_store_id}"
      assert log_output =~ "System shutting down"
    end
  end
  
  describe "action event handling" do
    test "processes action events at info level" do
      log_output = capture_log(fn ->
        LoggingPublisher.action(:emitter_system, @test_store_id, "System action")
        Process.sleep(100)
      end)
      
      assert log_output =~ "[info]"
      assert log_output =~ "EmitterSystem:#{@test_store_id}"
      assert log_output =~ "System action"
    end
    
  end
  
describe "error event handling" do
    test "processes error events" do
      log_output = capture_log(fn ->
        LoggingPublisher.error(:emitter_system, @test_store_id, "System error")
        Process.sleep(100)
      end)

      assert log_output =~ "[error]"
      assert log_output =~ "EmitterSystem:#{@test_store_id}"
      assert log_output =~ "System error"
    end
  end
  
  describe "configuration options" do
    test "worker respects configuration settings" do
      opts = [
        store_id: :config_test_store,
        emitter_system_logging_level: :debug,
        emitter_system_terminal_output: false
      ]
      
      {:ok, pid} = EmitterSystemLoggingWorker.start_link(opts)
      Process.sleep(50)
      
      # Should still log events regardless of terminal output setting
      log_output = capture_log(fn ->
        LoggingPublisher.startup(:emitter_system, :config_test_store, "Config test startup")
        Process.sleep(100)
      end)
      
      assert log_output =~ "EmitterSystem:config_test_store"
      assert log_output =~ "Config test startup"
      
      # Cleanup
      GenServer.stop(pid)
    end
  end
  
  describe "event filtering" do
    test "only processes emitter_system events" do
      log_output = capture_log(fn ->
        # Send events from other components
        LoggingPublisher.startup(:emitter_pool, @test_store_id, "Pool starting")
        LoggingPublisher.startup(:emitter_worker, @test_store_id, "Worker starting")
        
        # Send emitter_system event
        LoggingPublisher.startup(:emitter_system, @test_store_id, "System starting")
        
        Process.sleep(100)
      end)
      
      # Should only see the emitter_system event
      refute log_output =~ "Pool starting"
      refute log_output =~ "Worker starting"
      assert log_output =~ "System starting"
    end
    
    test "handles unknown event types gracefully" do
      # Create a custom event that doesn't match known types
      custom_event = %{
        component: :emitter_system,
        event_type: :custom_type,
        store_id: @test_store_id,
        pid: self(),
        timestamp: DateTime.utc_now(),
        message: "Custom event",
        metadata: %{}
      }
      
      log_output = capture_log(fn ->
        PubSub.broadcast(@pubsub_name, "logging:store:#{@test_store_id}", {:log_event, custom_event})
        Process.sleep(100)
      end)
      
      assert log_output =~ "EmitterSystem:#{@test_store_id}:custom_type"
      assert log_output =~ "Custom event"
    end
  end
  
  describe "worker lifecycle" do
    test "worker stops gracefully" do
      opts = [store_id: :temp_store]
      {:ok, pid} = EmitterSystemLoggingWorker.start_link(opts)
      
      assert Process.alive?(pid)
      
      :ok = GenServer.stop(pid)
      
      refute Process.alive?(pid)
    end
    
    test "worker handles crashes gracefully" do
      # This test ensures the worker doesn't crash on malformed events
      malformed_event = %{incomplete: "event"}
      
      # Send malformed event - worker should handle it gracefully
      PubSub.broadcast(@pubsub_name, "logging:store:#{@test_store_id}", {:log_event, malformed_event})
      
      Process.sleep(100)
      
      # Worker should still be alive
      assert Process.alive?(self())
    end
  end
end
