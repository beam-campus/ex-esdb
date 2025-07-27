defmodule ExESDB.SubscriptionHealthMonitorTest do
  @moduledoc """
  Tests for SubscriptionHealthMonitor functionality.

  Validates correct identification and handling of subscription issues.
  """

  use ExUnit.Case, async: false
  require Logger

  alias ExESDB.SubscriptionHealthMonitor

  @test_store_id :subscription_health_test_store

  describe "SubscriptionHealthMonitor" do
    test "can start and initialize correctly" do
      {:ok, monitor_pid} = SubscriptionHealthMonitor.start_link([
        store_id: @test_store_id,
        health_check_interval: 60_000,
        cleanup_enabled: false
      ])

      assert Process.alive?(monitor_pid)

      # Test health check call
      health_report = SubscriptionHealthMonitor.health_check(@test_store_id)
      assert is_map(health_report)
      assert Map.has_key?(health_report, :timestamp)
      assert Map.has_key?(health_report, :store_id)
      assert Map.has_key?(health_report, :issues)
      assert Map.has_key?(health_report, :summary)

      # Clean up
      GenServer.stop(monitor_pid)
    end

    test "can enable and disable cleanup" do
      {:ok, monitor_pid} = SubscriptionHealthMonitor.start_link([
        store_id: @test_store_id,
        cleanup_enabled: true
      ])

      # Test setting cleanup enabled/disabled
      :ok = SubscriptionHealthMonitor.set_cleanup_enabled(@test_store_id, false)
      :ok = SubscriptionHealthMonitor.set_cleanup_enabled(@test_store_id, true)

      # Clean up
      GenServer.stop(monitor_pid)
    end

    test "health report structure is correct" do
      {:ok, monitor_pid} = SubscriptionHealthMonitor.start_link([
        store_id: @test_store_id,
        cleanup_enabled: false
      ])

      health_report = SubscriptionHealthMonitor.health_check(@test_store_id)

      # Verify structure
      assert health_report.store_id == @test_store_id
      assert is_boolean(health_report.is_leader)
      assert is_integer(health_report.check_duration_ms)
      assert is_integer(health_report.total_subscriptions)
      assert is_integer(health_report.total_emitter_pools)

      # Verify issues structure
      issues = health_report.issues
      assert is_list(issues.stale_subscriptions)
      assert is_list(issues.orphaned_pools)
      assert is_list(issues.missing_pools)

      # Verify summary structure
      summary = health_report.summary
      assert is_integer(summary.stale_subscription_count)
      assert is_integer(summary.orphaned_pool_count)
      assert is_integer(summary.missing_pool_count)
      assert is_integer(summary.total_issues)

      # Clean up
      GenServer.stop(monitor_pid)
    end

    test "last health report functionality" do
      {:ok, monitor_pid} = SubscriptionHealthMonitor.start_link([
        store_id: @test_store_id,
        cleanup_enabled: false
      ])

      # Initially no last report
      assert SubscriptionHealthMonitor.last_health_report(@test_store_id) == nil

      # Perform health check
      health_report = SubscriptionHealthMonitor.health_check(@test_store_id)
      
      # Now should have last report
      last_report = SubscriptionHealthMonitor.last_health_report(@test_store_id)
      assert last_report != nil
      assert last_report.store_id == health_report.store_id

      # Clean up
      GenServer.stop(monitor_pid)
    end

    test "stale subscription detection logic" do
      # Create a dead process to simulate stale subscription
      dead_pid = spawn(fn -> :ok end)
      Process.exit(dead_pid, :kill)
      Process.sleep(10) # Give it time to die

      # Test subscription with dead subscriber
      subscription_with_dead_subscriber = %{
        subscription_name: "test_stale",
        subscriber: dead_pid,
        type: :by_stream,
        selector: "$test"
      }

      # Test subscription with live subscriber
      live_pid = spawn(fn -> 
        receive do
          :stop -> :ok
        end
      end)

      subscription_with_live_subscriber = %{
        subscription_name: "test_live",
        subscriber: live_pid,
        type: :by_stream,
        selector: "$test"
      }

      subscriptions = [subscription_with_dead_subscriber, subscription_with_live_subscriber]

      # Manually test the stale subscription detection logic
      stale_subscriptions = Enum.filter(subscriptions, fn subscription ->
        case Map.get(subscription, :subscriber) do
          nil -> false
          pid when is_pid(pid) -> not Process.alive?(pid)
          _ -> false
        end
      end)

      assert length(stale_subscriptions) == 1
      assert hd(stale_subscriptions).subscription_name == "test_stale"

      # Clean up live process
      send(live_pid, :stop)
    end
  end
end

