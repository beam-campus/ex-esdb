defmodule ExESDB.SubscriptionTestHelpers do
  @moduledoc """
  Shared utilities and helpers for testing the subscription mechanism.
  
  This module provides:
  - Mock subscriber processes
  - Event verification utilities
  - EmitterPool monitoring utilities
  - Leadership simulation helpers
  - Performance testing utilities
  """
  
  require Logger
  
  alias ExESDB.EmitterPool
  alias ExESDB.Emitters
  alias ExESDB.Topics
  alias ExESDB.StoreCluster
  
  @doc """
  Creates a mock subscriber process that collects events for testing.
  
  Returns: {subscriber_pid, collector_pid}
  The collector_pid can be used to retrieve collected events.
  """
  def create_mock_subscriber(test_pid \\ nil) do
    test_pid = test_pid || self()
    
    collector_pid = spawn_link(fn ->
      collect_events_loop([], test_pid)
    end)
    
    subscriber_pid = spawn_link(fn ->
      subscriber_loop(collector_pid)
    end)
    
    {subscriber_pid, collector_pid}
  end
  
  defp collect_events_loop(events, test_pid) do
    receive do
      {:add_event, event} ->
        updated_events = [event | events]
        collect_events_loop(updated_events, test_pid)
        
      {:get_events, caller_pid} ->
        send(caller_pid, {:events_collected, Enum.reverse(events)})
        collect_events_loop(events, test_pid)
        
      {:get_count, caller_pid} ->
        send(caller_pid, {:event_count, length(events)})
        collect_events_loop(events, test_pid)
        
      :clear ->
        collect_events_loop([], test_pid)
        
      :stop ->
        send(test_pid, {:collector_stopped, length(events)})
        :ok
    end
  end
  
  defp subscriber_loop(collector_pid) do
    receive do
      {:events, events} ->
        Enum.each(events, fn event ->
          send(collector_pid, {:add_event, event})
        end)
        subscriber_loop(collector_pid)
        
      :stop ->
        send(collector_pid, :stop)
        :ok
    end
  end
  
  @doc """
  Gets the collected events from a mock subscriber.
  """
  def get_collected_events(collector_pid, timeout \\ 1000) do
    send(collector_pid, {:get_events, self()})
    
    receive do
      {:events_collected, events} -> events
    after timeout ->
      []
    end
  end
  
  @doc """
  Gets the count of collected events from a mock subscriber.
  """
  def get_event_count(collector_pid, timeout \\ 1000) do
    send(collector_pid, {:get_count, self()})
    
    receive do
      {:event_count, count} -> count
    after timeout ->
      0
    end
  end
  
  @doc """
  Clears collected events from a mock subscriber.
  """
  def clear_collected_events(collector_pid) do
    send(collector_pid, :clear)
  end
  
  @doc """
  Stops a mock subscriber and returns the final event count.
  """
  def stop_mock_subscriber({subscriber_pid, collector_pid}, timeout \\ 1000) do
    send(subscriber_pid, :stop)
    send(collector_pid, :stop)
    
    receive do
      {:collector_stopped, count} -> count
    after timeout ->
      0
    end
  end
  
  @doc """
  Waits for an EmitterPool to start and returns its PID.
  """
  def wait_for_emitter_pool_start(store, sub_topic, timeout \\ 5000) do
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
  
  @doc """
  Waits for an EmitterPool to stop.
  """
  def wait_for_emitter_pool_stop(store, sub_topic, timeout \\ 5000) do
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
  
  @doc """
  Creates a test subscription directly in the store.
  """
  def create_direct_subscription(store, stream_id, subscription_name, subscriber_pid \\ nil, opts \\ []) do
    type = Keyword.get(opts, :type, :by_stream)
    selector = Keyword.get(opts, :selector, "$#{stream_id}")
    start_from = Keyword.get(opts, :start_from, 0)
    subscriber = subscriber_pid || self()
    
    subscription_data = %{
      type: type,
      selector: selector,
      subscription_name: subscription_name,
      start_from: start_from,
      subscriber: subscriber
    }
    
    result = :subscriptions_store.put_subscription(store, subscription_data)
    
    # Give time for triggers to fire
    Process.sleep(500)
    
    result
  end
  
  @doc """
  Deletes a test subscription directly from the store.
  """
  def delete_direct_subscription(store, stream_id, subscription_name, opts \\ []) do
    type = Keyword.get(opts, :type, :by_stream)
    selector = Keyword.get(opts, :selector, "$#{stream_id}")
    
    key = :subscriptions_store.key({type, selector, subscription_name})
    result = :khepri.delete!(store, [:subscriptions, key])
    
    # Give time for triggers to fire
    Process.sleep(500)
    
    result
  end
  
  @doc """
  Creates a test event with the given parameters.
  """
  def create_test_event(stream_id, event_type \\ "TestEvent", data \\ %{}) do
    %{
      event_id: "test-event-#{:rand.uniform(100000)}",
      event_type: event_type,
      event_data: data,
      stream_id: stream_id,
      event_timestamp: DateTime.utc_now(),
      event_version: 1
    }
  end
  
  @doc """
  Sends events directly to an EmitterWorker for testing.
  """
  def send_test_events_to_worker(worker_pid, sub_topic, events) when is_list(events) do
    Enum.each(events, fn event ->
      send(worker_pid, {:broadcast, sub_topic, event})
    end)
  end
  
  def send_test_events_to_worker(worker_pid, sub_topic, event) do
    send_test_events_to_worker(worker_pid, sub_topic, [event])
  end
  
  @doc """
  Gets all workers from an EmitterPool.
  """
  def get_emitter_workers(pool_pid) do
    children = Supervisor.which_children(pool_pid)
    
    Enum.map(children, fn {id, worker_pid, :worker, _modules} ->
      {id, worker_pid}
    end)
    |> Enum.filter(fn {_id, worker_pid} -> worker_pid != :undefined end)
  end
  
  @doc """
  Verifies that an EmitterPool has the expected number of workers.
  """
  def verify_emitter_pool_workers(pool_pid, expected_count) do
    workers = get_emitter_workers(pool_pid)
    actual_count = length(workers)
    
    if actual_count == expected_count do
      # Verify all workers are alive
      all_alive = Enum.all?(workers, fn {_id, worker_pid} -> 
        Process.alive?(worker_pid) 
      end)
      
      if all_alive do
        {:ok, workers}
      else
        {:error, :dead_workers}
      end
    else
      {:error, {:wrong_count, actual_count, expected_count}}
    end
  end
  
  @doc """
  Creates multiple test subscriptions concurrently.
  """
  def create_concurrent_subscriptions(store, base_name, count, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    tasks = Enum.map(1..count, fn i ->
      Task.async(fn ->
        stream_id = "#{base_name}_stream_#{i}"
        subscription_name = "#{base_name}_subscription_#{i}"
        
        result = create_direct_subscription(store, stream_id, subscription_name)
        
        if result == :ok do
          # Verify emitter pool started
          sub_topic = Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
          pool_pid = wait_for_emitter_pool_start(store, sub_topic, 5000)
          
          {stream_id, subscription_name, pool_pid != nil}
        else
          {stream_id, subscription_name, false}
        end
      end)
    end)
    
    Task.await_many(tasks, timeout)
  end
  
  @doc """
  Simulates high-throughput event processing.
  """
  def simulate_high_throughput(worker_pid, sub_topic, event_count, opts \\ []) do
    base_event = Keyword.get(opts, :base_event, create_test_event("throughput_test"))
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    
    start_time = System.monotonic_time(:millisecond)
    
    Enum.each(1..event_count, fn i ->
      event = Map.merge(base_event, %{
        event_id: "throughput-#{i}",
        event_data: Map.put(base_event.event_data, :sequence, i)
      })
      
      send(worker_pid, {:broadcast, sub_topic, event})
      
      if delay_ms > 0 do
        Process.sleep(delay_ms)
      end
    end)
    
    end_time = System.monotonic_time(:millisecond)
    end_time - start_time
  end
  
  @doc """
  Kills an EmitterWorker and waits for it to be restarted.
  """
  def kill_and_wait_for_restart(pool_pid, worker_id, timeout \\ 5000) do
    # Get initial worker
    workers = get_emitter_workers(pool_pid)
    {^worker_id, initial_worker_pid} = Enum.find(workers, fn {id, _pid} -> id == worker_id end)
    
    # Kill the worker
    Process.exit(initial_worker_pid, :kill)
    
    # Wait for restart
    Enum.find_value(1..div(timeout, 100), fn _ ->
      Process.sleep(100)
      workers = get_emitter_workers(pool_pid)
      
      case Enum.find(workers, fn {id, _pid} -> id == worker_id end) do
        {^worker_id, new_worker_pid} when new_worker_pid != initial_worker_pid ->
          if Process.alive?(new_worker_pid) do
            {:restarted, new_worker_pid}
          else
            nil
          end
        _ -> nil
      end
    end) || {:timeout, timeout}
  end
  
  @doc """
  Performs a comprehensive health check on an EmitterPool.
  """
  def health_check_emitter_pool(store, sub_topic, expected_workers \\ 1) do
    pool_name = EmitterPool.name(store, sub_topic)
    
    case Process.whereis(pool_name) do
      nil ->
        {:error, :pool_not_found}
        
      pool_pid ->
        if Process.alive?(pool_pid) do
          case verify_emitter_pool_workers(pool_pid, expected_workers) do
            {:ok, workers} ->
              # Test that workers can receive messages
              test_event = create_test_event("health_check")
              {_id, first_worker_pid} = List.first(workers)
              
              # Send test message (should not crash)
              send(first_worker_pid, {:broadcast, sub_topic, test_event})
              
              Process.sleep(100)
              
              if Process.alive?(first_worker_pid) do
                {:ok, %{
                  pool_pid: pool_pid,
                  workers: workers,
                  worker_count: length(workers)
                }}
              else
                {:error, :worker_crashed_on_message}
              end
              
            error -> error
          end
        else
          {:error, :pool_dead}
        end
    end
  end
  
  @doc """
  Measures the performance of subscription operations.
  """
  def benchmark_subscription_operations(store, operation_count, opts \\ []) do
    base_name = Keyword.get(opts, :base_name, "benchmark")
    
    # Measure creation time
    {creation_time_ms, created_subscriptions} = :timer.tc(fn ->
      create_concurrent_subscriptions(store, base_name, operation_count)
    end)
    creation_time_ms = div(creation_time_ms, 1000)
    
    successful_creations = Enum.count(created_subscriptions, fn {_, _, success} -> success end)
    
    # Measure deletion time (for successful creations)
    successful_subs = Enum.filter(created_subscriptions, fn {_, _, success} -> success end)
    
    {deletion_time_ms, _} = :timer.tc(fn ->
      Enum.each(successful_subs, fn {stream_id, subscription_name, _} ->
        delete_direct_subscription(store, stream_id, subscription_name)
      end)
    end)
    deletion_time_ms = div(deletion_time_ms, 1000)
    
    %{
      operation_count: operation_count,
      successful_creations: successful_creations,
      creation_time_ms: creation_time_ms,
      creation_ops_per_sec: if(creation_time_ms > 0, do: successful_creations * 1000 / creation_time_ms, else: 0),
      deletion_time_ms: deletion_time_ms,
      deletion_ops_per_sec: if(deletion_time_ms > 0, do: successful_creations * 1000 / deletion_time_ms, else: 0),
      total_time_ms: creation_time_ms + deletion_time_ms
    }
  end
  
  @doc """
  Sets up a test environment with mocked dependencies.
  """
  def setup_mocked_environment(test_pid \\ nil) do
    test_pid = test_pid || self()
    
    # Mock commonly used modules for testing
    :meck.new(:tracker_group, [:unstick])
    :meck.expect(:tracker_group, :notify_created, fn store, type, data -> 
      send(test_pid, {:mock_notify_created, store, type, data})
      :ok
    end)
    :meck.expect(:tracker_group, :notify_updated, fn store, type, data -> 
      send(test_pid, {:mock_notify_updated, store, type, data})
      :ok
    end)
    :meck.expect(:tracker_group, :notify_deleted, fn store, type, data -> 
      send(test_pid, {:mock_notify_deleted, store, type, data})
      :ok
    end)
    
    # Return cleanup function
    fn ->
      :meck.unload(:tracker_group)
    end
  end
  
  @doc """
  Generates unique identifiers for test isolation.
  """
  def generate_test_ids(prefix \\ "test") do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(100000)
    
    %{
      test_id: "#{prefix}_#{timestamp}_#{random}",
      stream_id: "stream_#{timestamp}_#{random}",
      subscription_name: "subscription_#{timestamp}_#{random}"
    }
  end
end
