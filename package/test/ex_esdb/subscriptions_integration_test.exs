defmodule ExESDB.SubscriptionsIntegrationTest do
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.SubscriptionsWriter
  alias ExESDB.SubscriptionsReader
  alias ExESDB.Schema.NewEvent
  
  @test_store_id :test_subscriptions_store
  @test_data_dir "/tmp/test_subscriptions_#{:rand.uniform(1000)}"
  
  setup_all do
    # Configure test environment
    opts = [
      store_id: @test_store_id,
      data_dir: @test_data_dir,
      timeout: 5000,
      db_type: :single,
      pub_sub: :test_pubsub,
      reader_idle_ms: 1000,
      writer_idle_ms: 1000
    ]
    
    Logger.info("Starting ExESDB.System for subscriptions integration tests with opts: #{inspect(opts)}")
    
    # Start the system
    {:ok, system_pid} = System.start_link(opts)
    
    # Wait for system to be ready
    Process.sleep(2000)
    
    on_exit(fn ->
      Logger.info("Stopping ExESDB.System for subscriptions integration tests")
      if Process.alive?(system_pid) do
        GenServer.stop(system_pid, :normal, 5000)
      end
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid, opts: opts}
  end
  
  describe "subscription system" do
    test "subscriptions system starts and is available" do
      # This is a basic test to verify the subscriptions system is running
      # The actual subscription API uses put_subscription with specific parameters
      
      Logger.info("Testing subscriptions system availability")
      
      stream_id = "test_stream_#{:rand.uniform(1000)}"
      subscription_name = "test_subscription_#{:rand.uniform(1000)}"
      
      # Test that we can create a subscription using the actual API
      # The API is: SubscriptionsWriter.put_subscription(store, type, selector, subscription_name, start_from, subscriber)
      result = SubscriptionsWriter.put_subscription(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",
        subscription_name,
        0,
        self()
      )
      
      # put_subscription returns :ok
      assert result == :ok
      
      Logger.info("Successfully tested subscriptions system basic functionality")
    end
    
    test "can create subscription with synchronous call" do
      stream_id = "test_stream_sync_#{:rand.uniform(1000)}"
      subscription_name = "test_subscription_sync_#{:rand.uniform(1000)}"
      
      Logger.info("Creating subscription synchronously: #{subscription_name} for stream: #{stream_id}")
      
      # Use the synchronous version to get a response
      result = SubscriptionsWriter.put_subscription_sync(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",
        subscription_name,
        0,
        self()
      )
      
      assert {:ok, _} = result
      Logger.info("Successfully created subscription #{subscription_name} for stream #{stream_id}")
    end
    
    test "can delete a subscription" do
      stream_id = "test_stream_delete_#{:rand.uniform(1000)}"
      subscription_name = "test_subscription_delete_#{:rand.uniform(1000)}"
      
      # Create subscription first
      {:ok, _} = SubscriptionsWriter.put_subscription_sync(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",
        subscription_name,
        0,
        self()
      )
      
      Logger.info("Deleting subscription: #{subscription_name}")
      
      # Delete the subscription
      result = SubscriptionsWriter.delete_subscription(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",
        subscription_name
      )
      
      assert result == :ok
      Logger.info("Successfully deleted subscription #{subscription_name}")
    end
    
    test "can list subscriptions" do
      # Create a subscription first
      stream_id = "test_stream_list_#{:rand.uniform(1000)}"
      subscription_name = "test_subscription_list_#{:rand.uniform(1000)}"
      
      {:ok, _} = SubscriptionsWriter.put_subscription_sync(
        @test_store_id,
        :by_stream,
        "$#{stream_id}",
        subscription_name,
        0,
        self()
      )
      
      Logger.info("Listing subscriptions for store: #{@test_store_id}")
      
      # List subscriptions
      result = SubscriptionsReader.get_subscriptions(@test_store_id)
      
      assert is_list(result)
      Logger.info("Successfully listed #{length(result)} subscriptions")
    end
  end
end
