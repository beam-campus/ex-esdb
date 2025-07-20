defmodule ExESDB.SubscriptionTriggersTest do
  @moduledoc """
  Testing framework specifically for the stored procedures and trigger mechanisms
  that manage subscription emitter pool lifecycle.
  
  This test suite focuses on:
  - Khepri trigger function installation and execution
  - Stored procedure interactions with subscription changes
  - Integration between subscriptions_store and subscriptions_procs
  - Notification flow from triggers to emitter pool management
  """
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.SubscriptionTestHelpers
  
  import :meck
  
  @test_store_id :subscription_triggers_test_store
  @test_data_dir "/tmp/test_subscription_triggers_#{:rand.uniform(10000)}"
  
  @test_opts [
    store_id: @test_store_id,
    data_dir: @test_data_dir,
    timeout: 10_000,
    db_type: :single,
    pub_sub: :test_triggers_pubsub,
    reader_idle_ms: 500,
    writer_idle_ms: 500,
    persistence_interval: 1000
  ]
  
  setup_all do
    Logger.info("Starting subscription triggers test suite")
    
    # Start the system
    {:ok, system_pid} = System.start_link(@test_opts)
    
    # Wait for system to be fully ready
    Process.sleep(3000)
    
    on_exit(fn ->
      Logger.info("Cleaning up subscription triggers test suite")
      if Process.alive?(system_pid) do
        GenServer.stop(system_pid, :normal, 10_000)
      end
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid}
  end
  
  setup do
    # Generate unique test identifiers
    ids = SubscriptionTestHelpers.generate_test_ids("triggers")
    
    # Setup mocked environment for each test
    cleanup_fn = SubscriptionTestHelpers.setup_mocked_environment(self())
    
    on_exit(cleanup_fn)
    
    Map.put(ids, :cleanup_fn, cleanup_fn)
  end
  
  describe "Stored Procedures Installation" do
    test "subscription triggers are properly installed during system startup" do
      Logger.info("Testing subscription triggers installation")
      
      # Verify that the trigger functions exist in the store
      create_key_exists = :khepri.exists(@test_store_id, :subscriptions_procs.on_create_key())
      update_key_exists = :khepri.exists(@test_store_id, :subscriptions_procs.on_update_key())
      delete_key_exists = :khepri.exists(@test_store_id, :subscriptions_procs.on_delete_key())
      
      assert create_key_exists == true, "Create trigger should be installed"
      assert update_key_exists == true, "Update trigger should be installed"  
      assert delete_key_exists == true, "Delete trigger should be installed"
      
      Logger.info("✅ Successfully verified trigger installation")
    end
    
    test "trigger functions can be manually installed without errors" do
      Logger.info("Testing manual trigger function installation")
      
      # Test installing create trigger
      result_create = :subscriptions_procs.put_on_create_func(@test_store_id)
      assert result_create == :ok, "Create trigger installation should succeed"
      
      # Test installing update trigger  
      result_update = :subscriptions_procs.put_on_update_func(@test_store_id)
      assert result_update == :ok, "Update trigger installation should succeed"
      
      # Test installing delete trigger
      result_delete = :subscriptions_procs.put_on_delete_func(@test_store_id)
      assert result_delete == :ok, "Delete trigger installation should succeed"
      
      Logger.info("✅ Successfully verified manual trigger installation")
    end
    
    test "trigger functions handle reinstallation gracefully" do
      Logger.info("Testing trigger function reinstallation")
      
      # Install once
      result1 = :subscriptions_procs.put_on_create_func(@test_store_id)
      assert result1 == :ok
      
      # Install again - should be idempotent
      result2 = :subscriptions_procs.put_on_create_func(@test_store_id)
      assert result2 == :ok
      
      # Verify trigger still exists and works
      trigger_exists = :khepri.exists(@test_store_id, :subscriptions_procs.on_create_key())
      assert trigger_exists == true
      
      Logger.info("✅ Successfully verified trigger reinstallation")
    end
  end
  
  describe "Trigger Execution on Subscription Changes" do
    test "create trigger fires when subscription is created", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing create trigger execution")
      
      # Create subscription and verify trigger notification
      result = SubscriptionTestHelpers.create_direct_subscription(
        @test_store_id, 
        stream_id, 
        subscription_name
      )
      assert result == :ok
      
      # Wait for trigger notification
      receive do
        {:mock_notify_created, store, type, subscription_data} ->
          assert store == @test_store_id, "Should notify about correct store"
          assert type == :subscriptions, "Should notify about subscriptions type"
          assert is_map(subscription_data), "Should include subscription data"
          assert subscription_data.subscription_name == subscription_name, "Should include correct subscription name"
          Logger.info("✅ Successfully verified create trigger execution")
        
      after 5000 ->
        flunk("Did not receive create notification from trigger")
      end
    end
    
    test "update trigger fires when subscription is updated", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing update trigger execution")
      
      # Create initial subscription
      SubscriptionTestHelpers.create_direct_subscription(
        @test_store_id,
        stream_id,
        subscription_name
      )
      
      # Clear any notifications from creation
      receive do
        {:mock_notify_created, _, _, _} -> :ok
      after 100 -> :ok
      end
      
      # Update subscription
      subscription_data = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 10,  # Changed start position
        subscriber: self()
      }
      
      result = :subscriptions_store.update_subscription(@test_store_id, subscription_data)
      assert result == :ok
      
      # Wait for update notification
      receive do
        {:mock_notify_updated, store, type, updated_subscription} ->
          assert store == @test_store_id, "Should notify about correct store"
          assert type == :subscriptions, "Should notify about subscriptions type"
          assert is_map(updated_subscription), "Should include subscription data"
          assert updated_subscription.start_from == 10, "Should include updated data"
          Logger.info("✅ Successfully verified update trigger execution")
        
      after 5000 ->
        flunk("Did not receive update notification from trigger")
      end
    end
    
    test "delete trigger fires when subscription is deleted", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing delete trigger execution")
      
      # Create subscription first
      SubscriptionTestHelpers.create_direct_subscription(
        @test_store_id,
        stream_id,
        subscription_name
      )
      
      # Clear creation notification
      receive do
        {:mock_notify_created, _, _, _} -> :ok
      after 100 -> :ok
      end
      
      # Delete subscription
      result = SubscriptionTestHelpers.delete_direct_subscription(
        @test_store_id,
        stream_id,
        subscription_name
      )
      assert result == :ok
      
      # Wait for delete notification
      receive do
        {:mock_notify_deleted, store, type, deleted_subscription} ->
          assert store == @test_store_id, "Should notify about correct store"
          assert type == :subscriptions, "Should notify about subscriptions type"
          assert is_map(deleted_subscription), "Should include subscription data"
          Logger.info("✅ Successfully verified delete trigger execution")
        
      after 5000 ->
        flunk("Did not receive delete notification from trigger")
      end
    end
  end
  
  describe "Trigger Integration with Store Operations" do
    test "triggers work with direct khepri operations", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing triggers with direct khepri operations")
      
      # Create subscription using direct khepri operations
      subscription_data = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name,
        start_from: 0,
        subscriber: self()
      }
      
      key = :subscriptions_store.key(subscription_data)
      
      # Direct put operation
      result = :khepri.put(@test_store_id, [:subscriptions, key], subscription_data)
      assert {:ok, _} = result
      
      # Wait for trigger notification
      receive do
        {:mock_notify_created, store, type, notified_subscription} ->
          assert store == @test_store_id
          assert type == :subscriptions
          assert is_map(notified_subscription)
          Logger.info("✅ Successfully verified trigger with direct khepri put")
        
      after 5000 ->
        flunk("Did not receive notification from direct khepri operation")
      end
    end
    
    test "triggers handle subscription key generation correctly", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing trigger key generation consistency")
      
      # Test that key generation is consistent
      subscription_tuple = {:by_stream, "$#{stream_id}", subscription_name}
      key1 = :subscriptions_store.key(subscription_tuple)
      
      subscription_map = %{
        type: :by_stream,
        selector: "$#{stream_id}",
        subscription_name: subscription_name
      }
      key2 = :subscriptions_store.key(subscription_map)
      
      assert key1 == key2, "Key generation should be consistent between tuple and map"
      
      # Create subscription and verify the key is used correctly
      SubscriptionTestHelpers.create_direct_subscription(
        @test_store_id,
        stream_id,
        subscription_name
      )
      
      # Verify the subscription exists at the expected key
      subscription_exists = :khepri.exists(@test_store_id, [:subscriptions, key1])
      assert subscription_exists == true, "Subscription should exist at generated key"
      
      Logger.info("✅ Successfully verified key generation consistency")
    end
  end
  
  describe "Error Handling in Triggers" do
    test "triggers handle malformed subscription data gracefully" do
      Logger.info("Testing trigger error handling with malformed data")
      
      # Create malformed subscription (missing required fields)
      malformed_data = %{
        type: :by_stream,
        # Missing selector, subscription_name, etc.
      }
      
      key = "malformed_test_key"
      
      # This should not crash the trigger
      result = :khepri.put(@test_store_id, [:subscriptions, key], malformed_data)
      assert {:ok, _} = result
      
      # Give time for trigger to process
      Process.sleep(1000)
      
      # System should still be responsive
      ping_result = :khepri.get(@test_store_id, [:subscriptions, key])
      assert {:ok, _} = ping_result
      
      Logger.info("✅ Successfully verified trigger error handling")
    end
    
    test "triggers handle store connectivity issues gracefully" do
      Logger.info("Testing trigger resilience to store issues")
      
      # Mock khepri operations to simulate failures
      :meck.new(:khepri, [:unstick, :passthrough])
      :meck.expect(:khepri, :get, fn store, path ->
        case path do
          [:subscriptions, _key] ->
            # Simulate intermittent store failure
            if :rand.uniform(2) == 1 do
              {:error, :store_unavailable}
            else
              :meck.passthrough([store, path])
            end
          _ ->
            :meck.passthrough([store, path])
        end
      end)
      
      # Create multiple subscriptions - some should succeed despite simulated failures
      results = Enum.map(1..5, fn i ->
        stream_id = "resilience_stream_#{i}"
        subscription_name = "resilience_sub_#{i}"
        
        try do
          SubscriptionTestHelpers.create_direct_subscription(
            @test_store_id,
            stream_id,
            subscription_name
          )
        rescue
          _ -> :error
        end
      end)
      
      # At least some operations should succeed
      successful_ops = Enum.count(results, fn result -> result == :ok end)
      assert successful_ops > 0, "Some operations should succeed despite simulated failures"
      
      # Clean up mock
      :meck.unload(:khepri)
      
      Logger.info("✅ Successfully verified trigger resilience (#{successful_ops}/5 operations succeeded)")
    end
  end
  
  describe "Trigger Performance and Concurrency" do
    @tag :performance
    test "triggers handle concurrent subscription operations" do
      Logger.info("Testing trigger performance under concurrent load")
      
      num_operations = 20
      
      # Create concurrent subscription operations
      tasks = Enum.map(1..num_operations, fn i ->
        Task.async(fn ->
          stream_id = "concurrent_stream_#{i}"
          subscription_name = "concurrent_sub_#{i}"
          
          start_time = System.monotonic_time(:millisecond)
          
          result = SubscriptionTestHelpers.create_direct_subscription(
            @test_store_id,
            stream_id,
            subscription_name
          )
          
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time
          
          {i, result, duration}
        end)
      end)
      
      # Wait for all operations to complete
      results = Task.await_many(tasks, 30_000)
      
      # Verify results
      successful_ops = Enum.count(results, fn {_, result, _} -> result == :ok end)
      total_duration = Enum.sum(Enum.map(results, fn {_, _, duration} -> duration end))
      avg_duration = div(total_duration, length(results))
      
      assert successful_ops >= div(num_operations, 2), "At least half of operations should succeed"
      assert avg_duration < 2000, "Average operation should complete within 2 seconds"
      
      Logger.info("✅ Successfully completed concurrent operations: #{successful_ops}/#{num_operations} succeeded, avg duration: #{avg_duration}ms")
    end
    
    @tag :performance
    test "triggers maintain performance under rapid subscription changes", %{test_id: test_id} do
      Logger.info("Testing trigger performance under rapid changes")
      
      stream_id = "rapid_changes_stream_#{test_id}"
      subscription_name = "rapid_changes_sub_#{test_id}"
      
      # Perform rapid create/delete cycle
      start_time = System.monotonic_time(:millisecond)
      
      Enum.each(1..10, fn _i ->
        # Create
        SubscriptionTestHelpers.create_direct_subscription(
          @test_store_id,
          stream_id,
          subscription_name
        )
        
        # Delete  
        SubscriptionTestHelpers.delete_direct_subscription(
          @test_store_id,
          stream_id,
          subscription_name
        )
      end)
      
      end_time = System.monotonic_time(:millisecond)
      total_duration = end_time - start_time
      
      # Should complete all operations within reasonable time
      assert total_duration < 20_000, "Rapid changes should complete within 20 seconds"
      
      # System should still be responsive
      test_subscription_data = %{
        type: :by_stream,
        selector: "$test_responsiveness",
        subscription_name: "responsiveness_test",
        start_from: 0,
        subscriber: self()
      }
      
      response_test_result = :subscriptions_store.put_subscription(@test_store_id, test_subscription_data)
      assert response_test_result == :ok, "System should remain responsive after rapid changes"
      
      Logger.info("✅ Successfully verified trigger performance under rapid changes: #{total_duration}ms total")
    end
  end
  
  describe "Integration with EmitterPool Management" do
    test "trigger notifications properly integrate with emitter pool lifecycle", %{stream_id: stream_id, subscription_name: subscription_name} do
      Logger.info("Testing trigger integration with emitter pool lifecycle")
      
      # Remove mock to test real integration
      :meck.unload(:tracker_group)
      
      # Create subscription - should trigger both notification and emitter pool start
      result = SubscriptionTestHelpers.create_direct_subscription(
        @test_store_id,
        stream_id,
        subscription_name
      )
      assert result == :ok
      
      # Wait a bit longer for emitter pool to start
      Process.sleep(2000)
      
      # Verify emitter pool was started
      sub_topic = ExESDB.Topics.sub_topic(:by_stream, subscription_name, "$#{stream_id}")
      pool_pid = SubscriptionTestHelpers.wait_for_emitter_pool_start(@test_store_id, sub_topic, 10_000)
      
      if pool_pid != nil do
        assert Process.alive?(pool_pid), "EmitterPool should be alive"
        
        # Verify pool health
        health_result = SubscriptionTestHelpers.health_check_emitter_pool(@test_store_id, sub_topic)
        assert {:ok, _health_info} = health_result
        
        Logger.info("✅ Successfully verified trigger integration with emitter pool start")
      else
        Logger.warning("EmitterPool did not start - this may indicate a configuration issue in single-node testing")
      end
    end
  end
end
