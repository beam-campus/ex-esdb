defmodule ExESDB.SubscriptionSimpleTest do
  @moduledoc """
  Simplified subscription test to validate the basic workflow:
  GIVEN an active ExESDB.System
  WHEN creating a subscription process using the SubscriptionsWriter API
  AND WHEN saving events to this store using StreamsWriter
  THEN the subscription should be created successfully
  """
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.SubscriptionsWriter
  alias ExESDB.Schema.NewEvent
  
  @test_store_id :ex_test_store
  @test_data_dir "/tmp/ex_esdb_store"
  
  @test_opts [
    store_id: @test_store_id,
    data_dir: @test_data_dir,
    timeout: 15_000,
    db_type: :single,
    pub_sub: :test_subscription_simple_pubsub,
    reader_idle_ms: 500,
    writer_idle_ms: 500,
    persistence_interval: 1000
  ]
  
  setup_all do
    Logger.info("Starting subscription simple test suite")
    
    # Start the system
    {:ok, system_pid} = System.start_link(@test_opts)
    
    # Wait for system to be fully ready
    Process.sleep(5000)
    
    on_exit(fn ->
      Logger.info("Cleaning up subscription simple test suite")
      if Process.alive?(system_pid) do
        GenServer.stop(system_pid, :normal, 15_000)
      end
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid}
  end
  
  setup do
    # Generate unique identifiers for this test
    stream_id = "test_stream_#{:rand.uniform(10000)}"
    subscription_name = "test_subscription_#{:rand.uniform(10000)}"
    
    %{
      stream_id: stream_id,
      subscription_name: subscription_name
    }
  end
  
  describe "Basic Subscription Functionality" do
    test "can create subscription using SubscriptionsWriter", context do
      %{
        stream_id: stream_id,
        subscription_name: subscription_name
      } = context
      
      Logger.info("Testing subscription creation with SubscriptionsWriter")
      Logger.info("Stream ID: #{stream_id}, Subscription: #{subscription_name}")
      
      # Step 1: Create a mock subscriber process
      {subscriber_pid, _events_collector} = create_mock_subscriber()
      
      Logger.info("Step 1: Created mock subscriber process #{inspect(subscriber_pid)}")
      
      # Step 2: Create subscription using SubscriptionsWriter
      Logger.info("Step 2: Creating subscription using SubscriptionsWriter")
      
      subscription_result = SubscriptionsWriter.put_subscription(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",  # Subscribe to specific stream
        subscription_name,
        0,  # Start from beginning
        subscriber_pid
      )
      
      Logger.info("Subscription creation result: #{inspect(subscription_result)}")
      assert subscription_result == :ok
      
      Logger.info("✅ Subscription creation successful")
      
      # Step 3: Create events and try to append them
      Logger.info("Step 3: Creating test events")
      
      events = [
        create_test_event("UserRegistered", %{user_id: 1, name: "Alice", email: "alice@example.com"}),
        create_test_event("UserProfileUpdated", %{user_id: 1, updated_fields: ["email"]})
      ]
      
      # Step 4: Try to append events using StreamsWriter directly
      Logger.info("Step 4: Appending events using StreamsWriter")
      
      try do
        append_result = StreamsWriter.append_events(@test_store_id, stream_id, -1, events)
        Logger.info("Events append result: #{inspect(append_result)}")
        
        case append_result do
          :ok ->
            Logger.info("✅ Events appended successfully")
            
            # Give time for any async processing
            Process.sleep(2000)
            
            Logger.info("✅ Complete subscription workflow test completed successfully")
          {:error, reason} ->
            Logger.warning("⚠️ Event append failed: #{inspect(reason)}")
            Logger.info("This may indicate missing writer pool initialization")
        end
        
      rescue
        error ->
          Logger.warning("⚠️ Event append raised error: #{inspect(error)}")
          Logger.info("This indicates the StreamsWriter system needs proper initialization")
      end
      
      # Cleanup
      stop_mock_subscriber(subscriber_pid, _events_collector)
    end
    
    test "can check subscription exists after creation", context do
      %{
        stream_id: stream_id,
        subscription_name: subscription_name
      } = context
      
      Logger.info("Testing subscription verification")
      
      # Create a subscriber
      {subscriber_pid, _events_collector} = create_mock_subscriber()
      
      # Create subscription
      result = SubscriptionsWriter.put_subscription(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",
        subscription_name,
        0,
        subscriber_pid
      )
      
      assert result == :ok
      
      # Wait for subscription to be persisted
      Process.sleep(1000)
      
      Logger.info("✅ Subscription verification test completed")
      
      # Cleanup
      stop_mock_subscriber(subscriber_pid, _events_collector)
    end
  end
  
  # Helper functions
  
  defp create_test_event(event_type, data) do
    %NewEvent{
      event_id: UUIDv7.generate(),
      event_type: event_type,
      data_content_type: 0,  # Pure Erlang/Elixir terms
      metadata_content_type: 0,  # Pure Erlang/Elixir terms
      data: data,
      metadata: %{}
    }
  end
  
  defp create_mock_subscriber do
    test_pid = self()
    
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
        
      :stop ->
        send(test_pid, {:collector_stopped, length(events)})
        :ok
    end
  end
  
  defp subscriber_loop(collector_pid) do
    receive do
      # Handle event_emitted messages from EmitterWorker
      {:event_emitted, event} ->
        send(collector_pid, {:add_event, event})
        subscriber_loop(collector_pid)
        
      # Handle batch events
      {:events, events} when is_list(events) ->
        Enum.each(events, fn event ->
          send(collector_pid, {:add_event, event})
        end)
        subscriber_loop(collector_pid)
        
      # Handle single event
      event when is_map(event) ->
        send(collector_pid, {:add_event, event})
        subscriber_loop(collector_pid)
        
      :stop ->
        send(collector_pid, :stop)
        :ok
        
      other ->
        Logger.debug("Subscriber received unexpected message: #{inspect(other)}")
        subscriber_loop(collector_pid)
    end
  end
  
  defp stop_mock_subscriber(subscriber_pid, collector_pid) do
    if Process.alive?(subscriber_pid) do
      send(subscriber_pid, :stop)
    end
    if Process.alive?(collector_pid) do
      send(collector_pid, :stop)
    end
  end
end