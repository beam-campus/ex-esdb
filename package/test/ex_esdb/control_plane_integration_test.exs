defmodule ExESDB.ControlPlaneIntegrationTest do
  use ExUnit.Case, async: false
  
  alias ExESDB.ControlPlane
  alias ExESDB.System
  
  @store_id :control_plane_integration_test_store
  
  setup do
    # Configure test store
    opts = [
      store_id: @store_id,
      db_type: :single,
      pub_sub: :native
    ]
    
    # Start the ExESDB system with Control Plane
    {:ok, system_pid} = System.start_link(opts)
    
    on_exit(fn ->
      if Process.alive?(system_pid) do
        Supervisor.stop(system_pid, :normal)
      end
    end)
    
    # Give the system time to start up completely
    Process.sleep(100)
    
    {:ok, system_pid: system_pid, opts: opts}
  end
  
  test "Control Plane is accessible after system startup", %{system_pid: system_pid} do
    assert Process.alive?(system_pid)
    
    # Should be able to get statistics
    stats = ControlPlane.stats()
    assert %{events_published: _, events_by_category: _, uptime_seconds: _, topics: _} = stats
  end
  
  test "Control Plane can publish and receive events within running system" do
    # Subscribe to cluster events
    :ok = ControlPlane.subscribe(@store_id, :cluster)
    
    # Publish a test event
    event_data = %{test: "integration", node: node()}
    :ok = ControlPlane.publish(@store_id, :cluster, :integration_test, event_data)
    
    # Should receive the event
    assert_received {:control_plane_event, %{
      event_type: :integration_test, 
      store_id: @store_id,
      data: ^event_data
    }}
  end
  
  test "Multiple components can subscribe to Control Plane events" do
    # Simulate multiple components subscribing
    parent = self()
    
    # Spawn test processes to simulate different components
    component1 = spawn_link(fn ->
      :ok = ControlPlane.subscribe(@store_id, :leadership)
      send(parent, {:component1, :subscribed})
      
      receive do
        {:control_plane_event, event} ->
          send(parent, {:component1, :received_event, event})
      after 1000 ->
        send(parent, {:component1, :timeout})
      end
    end)
    
    component2 = spawn_link(fn ->
      :ok = ControlPlane.subscribe(@store_id, :leadership)
      send(parent, {:component2, :subscribed})
      
      receive do
        {:control_plane_event, event} ->
          send(parent, {:component2, :received_event, event})
      after 1000 ->
        send(parent, {:component2, :timeout})
      end
    end)
    
    # Wait for subscriptions
    assert_received {:component1, :subscribed}
    assert_received {:component2, :subscribed}
    
    # Publish event
    :ok = ControlPlane.publish(@store_id, :leadership, :leader_elected, %{leader: node()})
    
    # Both components should receive the event
    assert_received {:component1, :received_event, %{event_type: :leader_elected}}
    assert_received {:component2, :received_event, %{event_type: :leader_elected}}
  end
  
  test "Control Plane maintains statistics correctly" do
    # Get initial stats
    initial_stats = ControlPlane.stats()
    initial_count = initial_stats.events_published
    
    # Subscribe to see our own events
    :ok = ControlPlane.subscribe(@store_id, :system)
    
    # Publish several events
    for i <- 1..3 do
      :ok = ControlPlane.publish(@store_id, :system, :test_event, %{sequence: i})
    end
    
    # Allow events to be processed
    Process.sleep(50)
    
    # Check updated stats
    updated_stats = ControlPlane.stats()
    assert updated_stats.events_published >= initial_count + 3
  end
  
  test "Control Plane handles topic isolation correctly" do
    # Subscribe to different categories
    :ok = ControlPlane.subscribe(@store_id, :cluster)
    :ok = ControlPlane.subscribe(@store_id, :leadership)
    
    # Publish to cluster topic
    :ok = ControlPlane.publish(@store_id, :cluster, :node_event, %{type: :cluster})
    
    # Should receive cluster event but not leadership event
    assert_received {:control_plane_event, %{event_type: :node_event, data: %{type: :cluster}}}
    
    # Publish to leadership topic
    :ok = ControlPlane.publish(@store_id, :leadership, :leader_event, %{type: :leadership})
    
    # Should receive leadership event
    assert_received {:control_plane_event, %{event_type: :leader_event, data: %{type: :leadership}}}
  end
  
  test "Control Plane isolates events by store_id" do
    another_store = :another_test_store
    
    # Subscribe to events for our store
    :ok = ControlPlane.subscribe(@store_id, :coordination)
    
    # Publish event for different store
    :ok = ControlPlane.publish(another_store, :coordination, :other_store_event, %{})
    
    # Should not receive event for different store
    refute_received {:control_plane_event, %{store_id: ^another_store}}
    
    # But should receive event for our store
    :ok = ControlPlane.publish(@store_id, :coordination, :our_store_event, %{})
    assert_received {:control_plane_event, %{store_id: @store_id, event_type: :our_store_event}}
  end
end
