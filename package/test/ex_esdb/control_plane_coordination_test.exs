defmodule ExESDB.ControlPlaneCoordinationTest do
  use ExUnit.Case, async: false

  alias ExESDB.ControlPlane

  @store_id :coordination_test_store

  setup do
    # Start PubSub with proper configuration
    start_supervised!({Phoenix.PubSub, name: ExESDB.PubSub})
    :ok
  end

  test "Control Plane coordinates system initialization" do
    # Subscribe to system events first
    :ok = ControlPlane.subscribe(@store_id, :system)
    
    # Now start the Control Plane after subscription
    start_supervised!({ControlPlane, [store_id: @store_id]})

    # Should receive initialization started event
    assert_receive {:control_plane_event, %{
      event_type: :initialization_started,
      store_id: @store_id,
      data: %{sequence: [:persistence, :notification, :store, :gateway]}
    }}, 1000

    # Should receive subsystem initialization events in sequence
    assert_receive {:control_plane_event, %{
      event_type: :subsystem_initialized,
      data: %{system: :persistence}
    }}, 1000

    assert_receive {:control_plane_event, %{
      event_type: :subsystem_initialized, 
      data: %{system: :notification}
    }}, 1000

    assert_receive {:control_plane_event, %{
      event_type: :subsystem_initialized,
      data: %{system: :store}
    }}, 1000

    assert_receive {:control_plane_event, %{
      event_type: :subsystem_initialized,
      data: %{system: :gateway}
    }}, 1000

    # Should receive system ready event when all systems are up
    assert_receive {:control_plane_event, %{
      event_type: :system_ready,
      data: %{managed_systems: systems}
    }}, 1000

    # All systems should be listed as managed (order doesn't matter)
    assert Enum.sort([:persistence, :notification, :store, :gateway]) == Enum.sort(systems)
  end

  test "Control Plane stats include system coordination info" do
    # Start Control Plane
    start_supervised!({ControlPlane, [store_id: @store_id]})
    
    # Wait for initialization to complete
    Process.sleep(500)
    
    stats = ControlPlane.stats()
    
    assert %{
      managed_systems: managed_systems,
      system_status: system_status,
      current_startup_step: startup_step
    } = stats
    
    # Should show systems as running after initialization
    assert system_status == :ready
    assert startup_step == 4  # All 4 systems processed
    assert map_size(managed_systems) == 4
  end

  test "Control Plane publishes events during coordination" do
    # Subscribe to system events first
    :ok = ControlPlane.subscribe(@store_id, :system)
    
    # Start Control Plane after subscription
    start_supervised!({ControlPlane, [store_id: @store_id]})
    
    # Should receive multiple coordination events
    events = collect_system_events(6)  # initialization + 4 systems + ready
    
    event_types = Enum.map(events, & &1.event_type)
    
    assert :initialization_started in event_types
    assert :system_ready in event_types
    
    # Should have 4 subsystem_initialized events
    subsystem_count = Enum.count(event_types, &(&1 == :subsystem_initialized))
    assert subsystem_count == 4
  end

  defp collect_system_events(count, events \\ []) when count > 0 do
    receive do
      {:control_plane_event, event} ->
        collect_system_events(count - 1, [event | events])
    after 2000 ->
      events
    end
  end
  
  defp collect_system_events(0, events), do: Enum.reverse(events)
end
