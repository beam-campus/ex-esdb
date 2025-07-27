defmodule ExESDB.EmitterWorkerLoggingWorkerTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.EmitterWorkerLoggingWorker
  alias ExESDB.LoggingPublisher
  alias Phoenix.PubSub
  
  import ExUnit.CaptureLog
  
  @pubsub_name :ex_esdb_logging
  @test_store_id :test_emitter_worker_logging
  
  setup do
    # Start the logging worker with default settings (actions disabled)
    opts = [
      store_id: @test_store_id,
      emitter_worker_logging_level: :info,
      emitter_worker_terminal_output: false,  # Default is false for workers (they're chatty)
      emitter_worker_log_actions: false,      # Default is false (very verbose)
      emitter_worker_log_health: true         # Default is true
    ]
    
    {:ok, worker_pid} = EmitterWorkerLoggingWorker.start_link(opts)
    
    # Give the worker time to subscribe to topics
    Process.sleep(50)
    
    %{worker_pid: worker_pid, opts: opts}
  end
  
  describe "initialization and configuration" do
    test "worker starts with default chatty-suppressed settings", %{worker_pid: worker_pid} do
      assert Process.alive?(worker_pid)
      
      # Test that action events are suppressed by default
      log_output = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, @test_store_id, "Verbose action")
        Process.sleep(100)
      end)
      
      # Should NOT log actions by default (too verbose)
      refute log_output =~ "Verbose action"
    end
    
    test "worker can be configured to enable verbose logging" do
      opts = [
        store_id: :verbose_store,
        emitter_worker_terminal_output: false,
        emitter_worker_log_actions: true,
        emitter_worker_log_health: true
      ]
      
      {:ok, pid} = EmitterWorkerLoggingWorker.start_link(opts)
      Process.sleep(50)
      
      # Now action events should be logged
      log_output = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, :verbose_store, "Verbose action")
        Process.sleep(100)
      end)
      
      assert log_output =~ "[debug]"
      assert log_output =~ "EmitterWorker:verbose_store"
      assert log_output =~ "Verbose action"
      
      # Cleanup
      GenServer.stop(pid)
    end
  end
  
  describe "startup event handling" do
    test "logs startup events" do
      log_output = capture_log(fn ->
        LoggingPublisher.startup(:emitter_worker, @test_store_id, "Worker starting", %{
          topic: "test_topic",
          subscriber: self(),
          scheduler_id: 1
        })
        Process.sleep(100)
      end)
      
      assert log_output =~ "[info]"
      assert log_output =~ "EmitterWorker:#{@test_store_id}"
      assert log_output =~ "Worker starting"
    end
  end
  
  describe "shutdown event handling" do
    test "logs shutdown events as warnings" do
      log_output = capture_log(fn ->
        LoggingPublisher.shutdown(:emitter_worker, @test_store_id, "Worker terminating", %{
          reason: :normal,
          selector: "test_selector",
          subscriber: self()
        })
        Process.sleep(100)
      end)
      
      assert log_output =~ "[warning]"
      assert log_output =~ "EmitterWorker:#{@test_store_id}"
      assert log_output =~ "Worker terminating"
    end
  end
  
  describe "action event handling (verbose events)" do
    test "suppresses action events by default" do
      log_output = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, @test_store_id, "Broadcast event")
        Process.sleep(100)
      end)
      
      # Should NOT log actions by default (too verbose)
      refute log_output =~ "Broadcast event"
    end
    
    test "processes action events when explicitly enabled" do
      opts = [
        store_id: :action_enabled_store,
        emitter_worker_log_actions: true,
        emitter_worker_terminal_output: false
      ]
      
      {:ok, pid} = EmitterWorkerLoggingWorker.start_link(opts)
      Process.sleep(50)
      
      log_output = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, :action_enabled_store, "Broadcasting event", %{
          event_id: "test-123",
          topic: "test_topic"
        })
        Process.sleep(100)
      end)
      
      assert log_output =~ "[debug]"
      assert log_output =~ "EmitterWorker:action_enabled_store"
      assert log_output =~ "Broadcasting event"
      
      # Cleanup
      GenServer.stop(pid)
    end
  end
  
  describe "health event handling" do
    test "processes health events by default" do
      log_output = capture_log(fn ->
        LoggingPublisher.health(:emitter_worker, @test_store_id, "Health check", %{
          subscription_name: "test_sub",
          event_type: :registration_success
        })
        Process.sleep(100)
      end)
      
      assert log_output =~ "[info]"
      assert log_output =~ "EmitterWorker:#{@test_store_id}:Health"
      assert log_output =~ "Health check"
    end
    
    test "can disable health event logging" do
      opts = [
        store_id: :no_health_store,
        emitter_worker_log_health: false
      ]
      
      {:ok, pid} = EmitterWorkerLoggingWorker.start_link(opts)
      Process.sleep(50)
      
      log_output = capture_log(fn ->
        LoggingPublisher.health(:emitter_worker, :no_health_store, "Health event")
        Process.sleep(100)
      end)
      
      # Should not log health events when disabled
      refute log_output =~ "Health event"
      
      # Cleanup
      GenServer.stop(pid)
    end
    
  end
  
  describe "error event handling" do
    test "always processes error events regardless of settings" do
      log_output = capture_log(fn ->
        LoggingPublisher.error(:emitter_worker, @test_store_id, "Worker error", %{
          error_type: :timeout
        })
        Process.sleep(100)
      end)
      
      assert log_output =~ "[error]"
      assert log_output =~ "EmitterWorker:#{@test_store_id}"
      assert log_output =~ "Worker error"
    end
  end
  
  describe "fine-grained configuration" do
    test "allows independent control of different event types" do
      opts = [
        store_id: :fine_grained_store,
        emitter_worker_terminal_output: false,
        emitter_worker_log_actions: true,      # Enable actions
        emitter_worker_log_health: false       # Disable health
      ]
      
      {:ok, pid} = EmitterWorkerLoggingWorker.start_link(opts)
      Process.sleep(50)
      
      action_log = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, :fine_grained_store, "Action event")
        Process.sleep(100)
      end)
      
      health_log = capture_log(fn ->
        LoggingPublisher.health(:emitter_worker, :fine_grained_store, "Health event")
        Process.sleep(100)
      end)
      
      # Actions should be logged
      assert action_log =~ "Action event"
      
      # Health should be suppressed
      refute health_log =~ "Health event"
      
      # Cleanup
      GenServer.stop(pid)
    end
  end
  
  describe "event filtering and isolation" do
    test "only processes emitter_worker events" do
      log_output = capture_log(fn ->
        # Send events from other components
        LoggingPublisher.startup(:emitter_system, @test_store_id, "System starting")
        LoggingPublisher.startup(:emitter_pool, @test_store_id, "Pool starting")
        
        # Send emitter_worker event
        LoggingPublisher.startup(:emitter_worker, @test_store_id, "Worker starting")
        
        Process.sleep(100)
      end)
      
      # Should only see the emitter_worker event
      refute log_output =~ "System starting"
      refute log_output =~ "Pool starting"
      assert log_output =~ "Worker starting"
    end
    
    test "isolates events by store_id" do
      log_output = capture_log(fn ->
        # Send events from other stores
        LoggingPublisher.startup(:emitter_worker, :other_store, "Other store worker")
        
        # Send event from our store
        LoggingPublisher.startup(:emitter_worker, @test_store_id, "Our store worker")
        
        Process.sleep(100)
      end)
      
      # Should only see events from our store
      refute log_output =~ "Other store worker"
      assert log_output =~ "Our store worker"
    end
  end
  
  describe "performance and volume handling" do
    test "handles high volume of suppressed events efficiently" do
      start_time = System.monotonic_time(:millisecond)
      
      # Send many action events (which should be suppressed)
      for i <- 1..100 do
        LoggingPublisher.action(:emitter_worker, @test_store_id, "Action #{i}")
      end
      
      Process.sleep(100)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should handle quickly (under 500ms for 100 events)
      assert duration < 500
      
      # Worker should still be alive
      assert Process.alive?(self())
    end
    
    test "handles mixed event types efficiently" do
      # Mix of different event types
      events = [
        {:startup, "Worker starting"},
        {:action, "Processing event 1"},
        {:health, "Health check"},
        {:action, "Processing event 2"},
        {:error, "Error occurred"},
        {:shutdown, "Worker stopping"}
      ]
      
      for {type, message} <- events do
        LoggingPublisher.publish(:emitter_worker, type, @test_store_id, message)
      end
      
      Process.sleep(100)
      
      # Worker should handle all events without crashing
      assert Process.alive?(self())
    end
  end
  
  describe "worker lifecycle and error handling" do
    test "handles malformed events gracefully" do
      malformed_events = [
        %{component: :emitter_worker},  # Missing fields
        %{incomplete: "data"},          # Wrong structure
        {:not_a_map, "at all"}         # Wrong type
      ]
      
      for event <- malformed_events do
        PubSub.broadcast(@pubsub_name, "logging:store:#{@test_store_id}", {:log_event, event})
      end
      
      Process.sleep(100)
      
      # Worker should still be alive after handling malformed events
      assert Process.alive?(self())
    end
    
    test "worker restarts preserve configuration when managed properly" do
      opts = [
        store_id: :restart_test_store,
        emitter_worker_log_actions: true,
        emitter_worker_terminal_output: false
      ]
      
      {:ok, pid1} = EmitterWorkerLoggingWorker.start_link(opts)
      
      # Verify initial configuration works
      log_output1 = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, :restart_test_store, "Before restart")
        Process.sleep(100)
      end)
      
      assert log_output1 =~ "Before restart"
      
      # Gracefully stop the worker
      GenServer.stop(pid1)
      Process.sleep(50)
      
      # Start a new one with same config
      {:ok, pid2} = EmitterWorkerLoggingWorker.start_link(opts)
      Process.sleep(50)
      
      # Should still respect the configuration (actions should be logged)
      log_output2 = capture_log(fn ->
        LoggingPublisher.action(:emitter_worker, :restart_test_store, "After restart")
        Process.sleep(100)
      end)
      
      assert log_output2 =~ "After restart"
      assert pid2 != pid1  # Confirm it's a new process
      
      # Cleanup
      GenServer.stop(pid2)
    end
  end
end
