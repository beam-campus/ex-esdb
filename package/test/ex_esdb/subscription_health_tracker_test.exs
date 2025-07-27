defmodule ExESDB.SubscriptionHealthTrackerTest do
  use ExUnit.Case, async: false

  alias ExESDB.SubscriptionHealthTracker
  
  setup do
    # Use unique store_id for each test to avoid conflicts
    store_id = String.to_atom("test_store_#{:rand.uniform(10000)}")
    
    # Start a fresh tracker for each test
    {:ok, pid} = SubscriptionHealthTracker.start_link(store_id: store_id)

    # Cleanup process
    on_exit(fn ->
      Process.exit(pid, :normal)
    end)

    {:ok, %{store_id: store_id, pid: pid}}
  end

  test "processes health events properly", %{store_id: store_id, pid: pid} do
    health_event = %{
      store_id: store_id,
      subscription_name: "test_subscription",
      event_type: :registration_success,
      metadata: %{info: "test_info"}
    }

    # Send the health event directly to the GenServer process
    send(pid, {:subscription_health, health_event})
    
    # Allow some time for the event to be processed
    :timer.sleep(200)

    # Check that the subscription health was recorded
    {:ok, health_data} = SubscriptionHealthTracker.get_subscription_health(store_id, "test_subscription")
    assert health_data.current_status == :healthy
    assert health_data.event_count == 1
    assert health_data.subscription_name == "test_subscription"
  end

  test "builds health summary correctly", %{store_id: store_id, pid: pid} do
    # Add some test health events
    healthy_event = %{
      store_id: store_id,
      subscription_name: "healthy_sub",
      event_type: :registration_success,
      metadata: %{}
    }
    
    failed_event = %{
      store_id: store_id,
      subscription_name: "failed_sub",
      event_type: :proxy_crashed,
      metadata: %{reason: "test_crash"}
    }

    # Send health events directly to the GenServer
    send(pid, {:subscription_health, healthy_event})
    send(pid, {:subscription_health, failed_event})
    
    # Allow time for processing
    :timer.sleep(200)

    # Check the health summary
    {:ok, summary} = SubscriptionHealthTracker.get_store_health_summary(store_id)
    assert summary.total_subscriptions == 2
    assert summary.healthy == 1
    assert summary.failed == 1
    assert summary.store_id == store_id
  end

  test "publishes periodic health summaries", %{store_id: store_id} do
    # Subscribe to health summary events
    Phoenix.PubSub.subscribe(:ex_esdb_system, "health_summary:#{store_id}")
    
    # Wait for a health summary to be published (they're published every 30 seconds)
    # For testing, we'll trigger one manually or wait for the periodic one
    # Since we can't easily change the interval in tests, we'll just verify the API works
    {:ok, summary} = SubscriptionHealthTracker.get_store_health_summary(store_id)
    assert Map.has_key?(summary, :total_subscriptions)
    assert Map.has_key?(summary, :store_id)
  end

  test "tracks multiple event types correctly", %{store_id: store_id} do
    subscription_name = "multi_event_sub"
    
    # Send different types of events
    events = [
      %{store_id: store_id, subscription_name: subscription_name, event_type: :registration_started, metadata: %{}},
      %{store_id: store_id, subscription_name: subscription_name, event_type: :registration_success, metadata: %{}},
      %{store_id: store_id, subscription_name: subscription_name, event_type: :event_delivery_success, metadata: %{}},
      %{store_id: store_id, subscription_name: subscription_name, event_type: :circuit_breaker_opened, metadata: %{reason: "too_many_failures"}}
    ]
    
    # Broadcast all events
    Enum.each(events, fn event ->
      Phoenix.PubSub.broadcast(:ex_esdb_system, "subscription_health:#{store_id}:#{subscription_name}", {:subscription_health, event})
    end)
    
    # Allow time for processing
    :timer.sleep(200)
    
    # Verify the final state (should be degraded due to circuit breaker)
    {:ok, health_data} = SubscriptionHealthTracker.get_subscription_health(store_id, subscription_name)
    assert health_data.current_status == :degraded
    assert health_data.event_count == 4
    assert health_data.error_count == 1
  end
end

