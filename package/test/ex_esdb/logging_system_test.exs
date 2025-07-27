defmodule ExESDB.LoggingSystemTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.LoggingSystem
  alias ExESDB.LoggingPublisher
  alias Phoenix.PubSub
  
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog
  
  @pubsub_name :ex_esdb_logging  
  @test_store_id :test_logging_system_integration
  
  setup do
    # Start the LoggingSystem
    opts = [
      store_id: @test_store_id,
      # Configure workers for testing
      emitter_system_terminal_output: true,
      emitter_pool_terminal_output: true,
      emitter_worker_terminal_output: false,  # Keep quiet by default
      emitter_worker_log_actions: false,      # Keep actions suppressed
      emitter_worker_log_health: true
    ]
    
    {:ok, system_pid} = LoggingSystem.start_link(opts)
    
    # Give the system time to start all workers
    Process.sleep(100)
    
    %{system_pid: system_pid, opts: opts}
  end
  
  describe "system initialization" do
    test "starts successfully and supervises all logging workers", %{system_pid: system_pid} do
      assert Process.alive?(system_pid)
      
      # Check that all expected children are running
      children = Supervisor.which_children(system_pid)
      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)
      
      expected_workers = [
        :"ex_esdb_emitter_system_logging_worker_#{@test_store_id}",
        :"ex_esdb_emitter_pool_logging_worker_#{@test_store_id}",
        :"ex_esdb_emitter_worker_logging_worker_#{@test_store_id}"
      ]
      
      for worker_id <- expected_workers do
        assert worker_id in child_ids, "Expected worker #{worker_id} to be running"
      end
      
      # Verify all workers are alive
      Enum.each(children, fn {_id, pid, _type, _modules} ->
        assert pid != :undefined
        assert Process.alive?(pid)
      end)
    end
    
    test "uses store-specific naming" do
      different_store = :different_logging_store
      opts = [store_id: different_store]
      
      {:ok, system2_pid} = LoggingSystem.start_link(opts)
      
      # Should be able to start multiple systems with different store IDs
      assert Process.alive?(system2_pid)
      
      # Cleanup
      GenServer.stop(system2_pid)
    end
  end
  
  describe "end-to-end logging flow" do
    test "processes emitter_system events from publish to output" do
      output = capture_io(fn ->
        log_output = capture_log(fn ->
          LoggingPublisher.startup(:emitter_system, @test_store_id, "System activation test", %{
            components: 3,
            max_restarts: "10/60s"
          })
          
          Process.sleep(150)  # Give time for processing
        end)
        
        # Should appear in Logger output
        assert log_output =~ "EmitterSystem:#{@test_store_id}"
        assert log_output =~ "System activation test"
      end)
      
      # Should appear in terminal output (configured as enabled)
      assert output =~ "🔥 EMITTER SYSTEM STARTUP 🔥"
      assert output =~ "System activation test"
      assert output =~ "Components: 3"
      assert output =~ "Max Restarts: 10/60s"
    end
    
    test "processes emitter_pool events from publish to output" do
      output = capture_io(fn ->
        log_output = capture_log(fn ->
          LoggingPublisher.startup(:emitter_pool, @test_store_id, "Pool startup test", %{
            pool_name: "test_pool",
            sub_topic: "test_topic",
            emitter_count: 5
          })
          
          Process.sleep(150)
        end)
        
        # Should appear in Logger output
        assert log_output =~ "EmitterPool:#{@test_store_id}"
        assert log_output =~ "Pool startup test"
      end)
      
      # Should appear in terminal output
      assert output =~ "🚀 EMITTER POOL STARTUP 🚀"
      assert output =~ "Pool startup test"
      assert output =~ "Pool Name: test_pool"
      assert output =~ "Workers:   5"
    end
    
    test "processes emitter_worker events with appropriate filtering" do
      # Worker actions should be suppressed by default
      action_output = capture_io(fn ->
        action_log = capture_log(fn ->
          LoggingPublisher.action(:emitter_worker, @test_store_id, "Worker action test")
          Process.sleep(150)
        end)
        
        # Should NOT appear in logs (actions suppressed)
        refute action_log =~ "Worker action test"
      end)
      
      # Should NOT appear in terminal (actions suppressed)
      assert action_output == ""
      
      # But health events should be processed
      health_output = capture_io(fn ->
        health_log = capture_log(fn ->
          LoggingPublisher.health(:emitter_worker, @test_store_id, "Worker health test")
          Process.sleep(150)
        end)
        
        # Should appear in logs (health enabled)
        assert health_log =~ "EmitterWorker:#{@test_store_id}:Health"
        assert health_log =~ "Worker health test"
      end)
      
      # Should NOT appear in terminal (terminal output disabled for workers)
      assert health_output == ""
    end
    
    test "handles mixed component events simultaneously" do
      events = [
        {:emitter_system, :startup, "System starting"},
        {:emitter_pool, :startup, "Pool starting"},
        {:emitter_worker, :startup, "Worker starting"},
        {:emitter_system, :action, "System action"},
        {:emitter_pool, :shutdown, "Pool stopping"},
        {:emitter_worker, :error, "Worker error"}
      ]
      
      output = capture_io(fn ->
        log_output = capture_log(fn ->
          # Send all events rapidly
          for {component, event_type, message} <- events do
            LoggingPublisher.publish(component, event_type, @test_store_id, message)
          end
          
          Process.sleep(200)  # Give time for all processing
        end)
        
        # Check that appropriate events appear in logs
        assert log_output =~ "System starting"
        assert log_output =~ "Pool starting"
        assert log_output =~ "Worker starting"
        assert log_output =~ "System action"
        assert log_output =~ "Pool stopping"
        assert log_output =~ "Worker error"
      end)
      
      # Check terminal output (only system and pool should show)
      assert output =~ "System starting"
      assert output =~ "Pool starting"
      assert output =~ "System action"
      assert output =~ "Pool stopping"
      
      # Worker events should not show in terminal (disabled)
      refute output =~ "Worker starting"
      # Worker errors should always show though
      assert output =~ "Worker error"
    end
  end
  
  describe "configuration propagation" do
    test "worker configuration is properly passed through" do
      # Start system with different configuration
      custom_opts = [
        store_id: :custom_config_store,
        emitter_worker_terminal_output: true,
        emitter_worker_log_actions: true,  # Enable actions
        emitter_system_terminal_output: false  # Disable system terminal
      ]
      
      {:ok, custom_system} = LoggingSystem.start_link(custom_opts)
      Process.sleep(100)
      
      # Test system events (terminal disabled)
      system_output = capture_io(fn ->
        LoggingPublisher.startup(:emitter_system, :custom_config_store, "Custom system")
        Process.sleep(150)
      end)
      
      assert system_output == ""  # Should be suppressed
      
      # Test worker events (terminal and actions enabled)
      worker_output = capture_io(fn ->
        LoggingPublisher.action(:emitter_worker, :custom_config_store, "Custom worker action")
        Process.sleep(150)
      end)
      
      assert worker_output =~ "Custom worker action"  # Should appear
      
      # Cleanup
      GenServer.stop(custom_system)
    end
  end
  
  describe "system resilience" do
    test "system recovers from worker crashes" do
      system_pid = self()
      
      # Get initial children
      initial_children = Supervisor.which_children(system_pid)
      initial_count = length(initial_children)
      
      # Find and kill one worker
      {_id, worker_pid, _type, _modules} = List.first(initial_children)
      Process.exit(worker_pid, :kill)
      
      # Give time for restart
      Process.sleep(200)
      
      # Check that worker was restarted
      new_children = Supervisor.which_children(system_pid)
      new_count = length(new_children)
      
      assert new_count == initial_count, "Worker should be restarted"
      
      # Verify all workers are alive
      Enum.each(new_children, fn {_id, pid, _type, _modules} ->
        assert pid != :undefined
        assert Process.alive?(pid)
      end)
      
      # Verify logging still works
      output = capture_io(fn ->
        LoggingPublisher.startup(:emitter_system, @test_store_id, "After restart")
        Process.sleep(150)
      end)
      
      assert output =~ "After restart"
    end
    
    test "handles high volume of events across all workers" do
      start_time = System.monotonic_time(:millisecond)
      
      # Send many events of different types
      for i <- 1..50 do
        LoggingPublisher.startup(:emitter_system, @test_store_id, "System #{i}")
        LoggingPublisher.startup(:emitter_pool, @test_store_id, "Pool #{i}")
        LoggingPublisher.health(:emitter_worker, @test_store_id, "Health #{i}")
      end
      
      Process.sleep(300)  # Give time for processing
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should handle efficiently (under 1 second for 150 events)
      assert duration < 1000
      
      # System should still be responsive
      response_output = capture_io(fn ->
        LoggingPublisher.startup(:emitter_system, @test_store_id, "Response test")
        Process.sleep(150)
      end)
      
      assert response_output =~ "Response test"
    end
  end
  
  describe "store isolation" do
    test "multiple stores operate independently" do
      # Start another LoggingSystem for a different store
      store2 = :isolated_store_2
      opts2 = [
        store_id: store2,
        emitter_system_terminal_output: true
      ]
      
      {:ok, system2_pid} = LoggingSystem.start_link(opts2)
      Process.sleep(100)
      
      # Send events to both stores
      output = capture_io(fn ->
        LoggingPublisher.startup(:emitter_system, @test_store_id, "Store 1 event")
        LoggingPublisher.startup(:emitter_system, store2, "Store 2 event")
        Process.sleep(200)
      end)
      
      # Both should appear in output (both have terminal enabled)
      assert output =~ "Store 1 event"
      assert output =~ "Store 2 event"
      
      # But they should be processed by their respective systems
      # (This is tested by the fact that both appear - if isolation was broken,\n      # one system might not process events from the other store)
      
      # Cleanup
      GenServer.stop(system2_pid)
    end
  end
  
  describe "PubSub integration" do
    test "events are properly routed through PubSub topics" do
      # Subscribe directly to PubSub topics to verify routing
      component_topic = "logging:emitter_system"
      store_topic = "logging:store:#{@test_store_id}"
      
      :ok = PubSub.subscribe(@pubsub_name, component_topic)
      :ok = PubSub.subscribe(@pubsub_name, store_topic)
      
      # Publish an event
      LoggingPublisher.startup(:emitter_system, @test_store_id, "PubSub test")
      
      # Should receive on both topics
      assert_receive {:log_event, component_event}, 100
      assert_receive {:log_event, store_event}, 100
      
      # Events should be identical
      assert component_event == store_event
      assert component_event.component == :emitter_system
      assert component_event.message == "PubSub test"
      
      # And should also be processed by the logging workers
      # (which we can verify by the terminal output)
      output = capture_io(fn ->
        Process.sleep(150)
      end)
      
      assert output =~ "PubSub test"
    end
  end
  
  describe "graceful shutdown" do
    test "system shuts down cleanly" do
      system_pid = self()
      
      # Verify system is running
      assert Process.alive?(system_pid)
      
      # Send some events to ensure workers are active
      LoggingPublisher.startup(:emitter_system, @test_store_id, "Before shutdown")
      Process.sleep(100)
      
      # Stop the system
      :ok = GenServer.stop(system_pid)
      
      # System should be stopped
      refute Process.alive?(system_pid)
    end
  end
end
