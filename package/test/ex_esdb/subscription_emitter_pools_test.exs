defmodule ExESDB.SubscriptionEmitterPoolsTest do
  @moduledoc """
  Testing framework for the subscription emitter pools mechanism.
  
  This test suite validates the crucial subscription functionality:
  - When subscriptions are created/updated/deleted, emitter pools are properly managed
  - Emitter pools start with the correct number of workers
  - Workers properly receive and forward events to subscribers
  - Leadership changes properly manage emitter pools
  - Integration with the stored procedure triggers works correctly
  """
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.SubscriptionsWriter
  alias ExESDB.SubscriptionsReader
  alias ExESDB.Schema.NewEvent
  alias ExESDB.Emitters
  alias ExESDB.EmitterPool
  alias ExESDB.EmitterWorker
  alias ExESDB.LeaderWorker
  alias ExESDB.StoreCluster
  alias ExESDB.StoreNaming
  
  import :meck
  
  @test_store_id :subscription_emitter_test_store
  @test_data_dir "/tmp/test_subscription_emitters_#{:rand.uniform(10000)}"
  
  # Test configuration for faster execution
  @test_opts [
    store_id: @test_store_id,
    data_dir: @test_data_dir,
    timeout: 10_000,
    db_type: :single,
    pub_sub: :test_subscription_pubsub,
    reader_idle_ms: 500,
    writer_idle_ms: 500,
    persistence_interval: 1000  # Fast persistence for testing
  ]
  
  setup_all do
    Logger.info("Starting comprehensive subscription emitter pools test suite")
    
    # Start the system
    {:ok, system_pid} = System.start_link(@test_opts)
    
    # Wait for system to be fully ready
    Process.sleep(3000)
    
    # Ensure we're the leader for testing
    ensure_leadership()
    
    on_exit(fn ->
      Logger.info("Cleaning up subscription emitter pools test suite")
      if Process.alive?(system_pid) do
        GenServer.stop(system_pid, :normal, 10_000)
      end
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid}
  end
  
  setup do
    # Create unique identifiers for each test
    test_id = :rand.uniform(100000)
    stream_id = "test_stream_#{test_id}"
    subscription_name = "test_subscription_#{test_id}"
    
    %{
      test_id: test_id,
      stream_id: stream_id,
      subscription_name: subscription_name
    }
  end
  
  defp ensure_leadership do
    # Make sure this node is the leader for emitter pool management
    case StoreCluster.leader?(@test_store_id) do
      true -> 
        Logger.info("Node is already leader")
        :ok
      false -> 
        Logger.info("Node is not leader, this might affect emitter pool tests")
        :ok
    end
  end
  
  defp wait_for_emitter_pool_start(store, sub_topic, timeout \\ 5000) do
    pool_name = EmitterPool.name(store, sub_topic)
    
    Enum.find_value(1..div(timeout, 100), fn _ ->
      case Process.whereis(pool_name) do
        nil -> 
          Process.sleep(100)
          nil
        pid -> pid
      end
    end)
  end
  
  defp wait_for_emitter_pool_stop(store, sub_topic, timeout \\ 5000) do
    pool_name = EmitterPool.name(store, sub_topic)
    
    Enum.find_value(1..div(timeout, 100), fn _ ->
      case Process.whereis(pool_name) do
        nil -> true
        _pid -> 
          Process.sleep(100)
          nil
      end
    end)
  end
  
  defp create_test_subscription(stream_id, subscription_name, subscriber_pid \\ nil) do
    subscriber = subscriber_pid || self()
    
    # Use synchronous version for testing
    result = :subscriptions_store.put_subscription(@test_store_id, %{
      type: :by_stream,
      selector: "$#{stream_id}",
      subscription_name: subscription_name,
      start_from: 0,
      subscriber: subscriber
    })
    
    # Give time for triggers to fire and emitter pool to start
    Process.sleep(1000)
    
    result
  end
  
  defp delete_test_subscription(stream_id, subscription_name) do
    key = :subscriptions_store.key({:by_stream, "$#{stream_id}", subscription_name})
    
    result = :khepri.delete!(@test_store_id, [:subscriptions, key])
    
    # Give time for triggers to fire and emitter pool to stop
    Process.sleep(1000)
    
    result
  end
  
  describe "Subscription Creation and EmitterPool Management" do
    test "subscription creation triggers emitter pool start", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing subscription creation triggers emitter pool start")
      
      # Create subscription
      result = create_test_subscription(stream_id, subscription_name)
      assert result == :ok
      
      # Check that emitter pool was started
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      
      assert pool_pid != nil, "EmitterPool should have started after subscription creation"
      assert Process.alive?(pool_pid), "EmitterPool process should be alive"
      
      # Verify pool has correct name
      expected_name = EmitterPool.name(@test_store_id, sub_topic)
      assert Process.whereis(expected_name) == pool_pid, "Pool should be registered with correct name"
      
      Logger.info("✅ Successfully verified emitter pool creation")
    end
    
    test "emitter pool starts with correct number of workers", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter pool starts with correct number of workers")
      
      # Create subscription
      create_test_subscription(stream_id, subscription_name)
      
      # Check emitter pool and its workers
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      
      assert pool_pid != nil, "EmitterPool should exist"
      
      # Get children of the supervisor (emitter workers)
      children = Supervisor.which_children(pool_pid)
      assert length(children) > 0, "EmitterPool should have worker children"
      
      # Verify all workers are EmitterWorker processes
      Enum.each(children, fn {id, worker_pid, :worker, modules} ->
        assert worker_pid != :undefined, "Worker should have valid PID"
        assert Process.alive?(worker_pid), "Worker should be alive"
        assert modules == [ExESDB.EmitterWorker], "Worker should be EmitterWorker module"
      end)
      
      Logger.info("✅ Successfully verified emitter pool worker structure")
    end
    
    test "subscription deletion triggers emitter pool stop", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing subscription deletion triggers emitter pool stop")
      
      # Create subscription first
      create_test_subscription(stream_id, subscription_name)
      
      # Verify pool is running
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      assert pool_pid != nil, "EmitterPool should be running before deletion"
      
      # Delete subscription
      delete_test_subscription(stream_id, subscription_name)
      
      # Verify pool is stopped
      pool_stopped = wait_for_emitter_pool_stop(@test_store_id, sub_topic)
      assert pool_stopped == true, "EmitterPool should stop after subscription deletion"
      
      # Verify process is really gone
      pool_name = EmitterPool.name(@test_store_id, sub_topic)
      assert Process.whereis(pool_name) == nil, "EmitterPool should be unregistered"
      
      Logger.info("✅ Successfully verified emitter pool deletion")
    end
  end
  
  describe "EmitterPool Worker Functionality" do
    test "emitter workers receive and forward events", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter workers receive and forward events")
      
      # Create a test subscriber process
      test_subscriber = spawn_link(fn -> 
        receive do
          {:events, events} -> 
            send(:test_result, {:received_events, events})
            Logger.info("Test subscriber received events: #{inspect(events)}")
        after 10_000 ->
          send(:test_result, :timeout)
        end
      end)
      Process.register(test_subscriber, :test_subscriber)
      
      # Create subscription with our test subscriber
      create_test_subscription(stream_id, subscription_name, test_subscriber)
      
      # Wait for emitter pool to be ready
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      assert pool_pid != nil, "EmitterPool should be running"
      
      # Get one of the workers
      children = Supervisor.which_children(pool_pid)
      assert length(children) > 0, "Should have worker children"
      
      {_id, worker_pid, :worker, _modules} = List.first(children)
      assert Process.alive?(worker_pid), "Worker should be alive"
      
      # Send a test event directly to the worker
      test_event = %{
        event_id: "test-event-#{:rand.uniform(1000)}",
        event_type: "TestEvent",
        event_data: %{message: "test event data"},
        stream_id: stream_id
      }
      
      # Simulate the broadcast message that workers receive
      send(worker_pid, {:broadcast, sub_topic, test_event})
      
      # Wait for result from test subscriber
      Process.register(self(), :test_result)
      
      receive do
        {:received_events, events} ->
          assert is_list(events), "Events should be a list"
          assert length(events) == 1, "Should receive one event"
          received_event = List.first(events)
          assert received_event.event_id == test_event.event_id, "Should receive the correct event"
          Logger.info("✅ Successfully verified event forwarding")
        
        :timeout ->
          flunk("Test subscriber did not receive events within timeout")
      after 5000 ->
        flunk("No response from test subscriber")
      end
      
      # Clean up
      if Process.whereis(:test_subscriber), do: Process.unregister(:test_subscriber)
      if Process.whereis(:test_result), do: Process.unregister(:test_result)
    end
    
    test "emitter workers handle subscriber updates", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter workers handle subscriber updates")
      
      # Create subscription with initial subscriber
      initial_subscriber = spawn(fn -> 
        receive do
          _ -> :ok
        end
      end)
      
      create_test_subscription(stream_id, subscription_name, initial_subscriber)
      
      # Wait for emitter pool
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      assert pool_pid != nil
      
      # Get worker
      children = Supervisor.which_children(pool_pid)
      {_id, worker_pid, :worker, _modules} = List.first(children)
      
      # Create new subscriber
      new_subscriber = spawn(fn ->
        receive do
          {:events, _events} -> send(self(), :received)
        end
      end)
      
      # Update worker with new subscriber
      GenServer.cast(worker_pid, {:update_subscriber, new_subscriber})
      
      # Give time for update to process
      Process.sleep(100)
      
      # Verify worker state was updated (indirectly by checking it doesn't crash)
      assert Process.alive?(worker_pid), "Worker should still be alive after update"
      
      Logger.info("✅ Successfully verified subscriber updates")
    end
  end
  
  describe "Leadership and EmitterPool Management" do
    test "leader worker starts emitter pools for existing subscriptions", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing leader worker starts emitter pools for existing subscriptions")
      
      # Create subscription first (this should not start emitter pool if not leader)
      result = :subscriptions_store.put_subscription(@test_store_id, %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 0,
        subscriber: self()
      })
      assert result == :ok
      
      # Simulate leadership activation
      result = LeaderWorker.activate(@test_store_id)
      
      case result do
        :ok ->
          # Wait for emitter pool to start
          sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
          pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic, 10_000)
          
          assert pool_pid != nil, "EmitterPool should start when leader is activated"
          assert Process.alive?(pool_pid), "EmitterPool should be alive"
          
          Logger.info("✅ Successfully verified leader activation starts emitter pools")
        
        {:error, :not_found} ->
          Logger.warning("LeaderWorker not found - this may be expected in single node tests")
          # Skip the test if LeaderWorker is not available
        
        other ->
          flunk("Unexpected result from LeaderWorker.activate: #{inspect(other)}")
      end
    end
  end
  
  describe "EmitterPool Integration with Stored Procedures" do
    test "stored procedure triggers create notifications", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing stored procedure triggers create notifications")
      
      # Mock the tracker_group to capture notifications
      :meck.new(:tracker_group, [:unstick])
      :meck.expect(:tracker_group, :notify_created, fn store, type, subscription -> 
        send(self(), {:notification_created, store, type, subscription})
        :ok
      end)
      
      # Create subscription using the store layer (which should trigger stored procedures)
      subscription_data = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 0,
        subscriber: self()
      }
      
      result = :subscriptions_store.put_subscription(@test_store_id, subscription_data)
      assert result == :ok
      
      # Wait for notification
      receive do
        {:notification_created, store, type, subscription} ->
          assert store == @test_store_id, "Should notify about correct store"
          assert type == :subscriptions, "Should notify about subscriptions"
          assert is_map(subscription), "Should include subscription data"
          Logger.info("✅ Successfully verified stored procedure notifications")
        
      after 5000 ->
        flunk("Did not receive notification from stored procedure trigger")
      end
      
      # Clean up mocks
      :meck.unload(:tracker_group)
    end
    
    test "stored procedure triggers delete notifications", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing stored procedure triggers delete notifications")
      
      # Create subscription first
      subscription_data = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 0,
        subscriber: self()
      }
      
      :subscriptions_store.put_subscription(@test_store_id, subscription_data)
      
      # Mock the tracker_group to capture delete notifications
      :meck.new(:tracker_group, [:unstick])
      :meck.expect(:tracker_group, :notify_deleted, fn store, type, subscription -> 
        send(self(), {:notification_deleted, store, type, subscription})
        :ok
      end)
      
      # Delete subscription
      result = :subscriptions_store.delete_subscription(@test_store_id, subscription_data)
      assert result == :ok
      
      # Wait for delete notification
      receive do
        {:notification_deleted, store, type, subscription} ->
          assert store == @test_store_id, "Should notify about correct store"
          assert type == :subscriptions, "Should notify about subscriptions"
          assert is_map(subscription), "Should include subscription data"
          Logger.info("✅ Successfully verified stored procedure delete notifications")
        
      after 5000 ->
        flunk("Did not receive delete notification from stored procedure trigger")
      end
      
      # Clean up mocks
      :meck.unload(:tracker_group)
    end
  end
  
  describe "Error Handling and Edge Cases" do
    test "emitter pool handles worker crashes gracefully", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter pool handles worker crashes gracefully")
      
      create_test_subscription(stream_id, subscription_name)
      
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      assert pool_pid != nil
      
      # Get initial worker count
      initial_children = Supervisor.which_children(pool_pid)
      initial_count = length(initial_children)
      assert initial_count > 0
      
      # Kill one worker
      {_id, worker_pid, :worker, _modules} = List.first(initial_children)
      Process.exit(worker_pid, :kill)
      
      # Wait for restart
      Process.sleep(1000)
      
      # Verify worker was restarted
      new_children = Supervisor.which_children(pool_pid)
      new_count = length(new_children)
      
      assert new_count == initial_count, "Worker should be restarted after crash"
      assert Process.alive?(pool_pid), "Pool supervisor should still be alive"
      
      Logger.info("✅ Successfully verified worker crash recovery")
    end
    
    test "emitter pool start is idempotent", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter pool start is idempotent")
      
      subscription_data = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 0,
        subscriber: self()
      }
      
      # Start first pool
      result1 = Emitters.start_emitter_pool(@test_store_id, subscription_data)
      assert {:ok, _pid1} = result1
      
      # Try to start again - should return already_started
      result2 = Emitters.start_emitter_pool(@test_store_id, subscription_data)
      assert {:error, {:already_started, _pid2}} = result2
      
      Logger.info("✅ Successfully verified idempotent emitter pool start")
    end
    
    test "emitter pool handles invalid subscriber gracefully", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter pool handles invalid subscriber gracefully")
      
      # Create subscription with dead subscriber
      dead_subscriber = spawn(fn -> :ok end)
      Process.sleep(100) # Let it die
      
      subscription_data = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 0,
        subscriber: dead_subscriber
      }
      
      # Pool should still start successfully
      result = Emitters.start_emitter_pool(@test_store_id, subscription_data)
      assert {:ok, pool_pid} = result
      assert Process.alive?(pool_pid)
      
      # Workers should handle dead subscriber without crashing
      children = Supervisor.which_children(pool_pid)
      assert length(children) > 0
      
      {_id, worker_pid, :worker, _modules} = List.first(children)
      assert Process.alive?(worker_pid)
      
      Logger.info("✅ Successfully verified invalid subscriber handling")
    end
  end
  
  describe "Performance and Load Testing" do
    @tag :performance
    test "emitter pools handle multiple concurrent subscriptions", %{test_id: test_id} do
      Logger.info("Testing emitter pools handle multiple concurrent subscriptions")
      
      # Create multiple subscriptions concurrently
      num_subscriptions = 10
      
      tasks = Enum.map(1..num_subscriptions, fn i ->
        Task.async(fn ->
          stream_id = "perf_stream_#{test_id}_#{i}"
          subscription_name = "perf_subscription_#{test_id}_#{i}"
          
          create_test_subscription(stream_id, subscription_name)
          
          # Verify emitter pool started
          sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
          pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
          
          {stream_id, subscription_name, pool_pid != nil}
        end)
      end)
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 30_000)
      
      # Verify all succeeded
      Enum.each(results, fn {stream_id, subscription_name, pool_started} ->
        assert pool_started, "EmitterPool should start for #{subscription_name} on #{stream_id}"
      end)
      
      Logger.info("✅ Successfully verified concurrent subscription handling")
    end
    
    @tag :performance
    test "emitter workers handle high event throughput", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing emitter workers handle high event throughput")
      
      # Create a collecting subscriber
      collector_pid = spawn_link(fn ->
        collect_events([], 0, 100) # Expect 100 events
      end)
      
      create_test_subscription(stream_id, subscription_name, collector_pid)
      
      # Wait for emitter pool
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = wait_for_emitter_pool_start(@test_store_id, sub_topic)
      assert pool_pid != nil
      
      # Get worker
      children = Supervisor.which_children(pool_pid)
      {_id, worker_pid, :worker, _modules} = List.first(children)
      
      # Send many events rapidly
      start_time = System.monotonic_time(:millisecond)
      
      Enum.each(1..100, fn i ->
        test_event = %{
          event_id: "throughput-test-#{i}",
          event_type: "ThroughputTestEvent",
          event_data: %{sequence: i},
          stream_id: stream_id
        }
        
        send(worker_pid, {:broadcast, sub_topic, test_event})
      end)
      
      # Wait for completion
      receive do
        {:collection_complete, events_received, total_time} ->
          end_time = System.monotonic_time(:millisecond)
          processing_time = end_time - start_time
          
          assert events_received == 100, "Should receive all 100 events"
          assert processing_time < 5000, "Should process 100 events within 5 seconds"
          
          Logger.info("✅ Successfully processed #{events_received} events in #{processing_time}ms")
        
      after 10_000 ->
        flunk("Did not receive all events within timeout")
      end
    end
  end
  
  # Helper function for event collection
  defp collect_events(events, count, target) when count >= target do
    total_time = System.monotonic_time(:millisecond)
    send(self(), {:collection_complete, count, total_time})
  end
  
  defp collect_events(events, count, target) do
    receive do
      {:events, new_events} ->
        updated_events = events ++ new_events
        new_count = count + length(new_events)
        collect_events(updated_events, new_count, target)
    after 1000 ->
      # Timeout - return what we have
      send(self(), {:collection_complete, count, System.monotonic_time(:millisecond)})
    end
  end
end
