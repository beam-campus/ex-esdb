defmodule ExESDB.ControlPlaneTest do
  use ExUnit.Case, async: false

  alias ExESDB.ControlPlane

  @store_id :test_store

  setup do
    # Start PubSub with proper configuration
    start_supervised!({Phoenix.PubSub, name: ExESDB.PubSub})
    # Ensure Control Plane is started
    start_supervised!(ControlPlane)
    :ok
  end

  test "publish and subscribe to events" do
    :ok = ControlPlane.subscribe(@store_id, :cluster)

    event_data = %{node: node()}
    :ok = ControlPlane.publish(@store_id, :cluster, :node_joined, event_data)

    assert_received {:control_plane_event, %{event_type: :node_joined, data: ^event_data}}
  end

  test "duplicate category subscriptions don't fail" do
    assert :ok == ControlPlane.subscribe(@store_id, :cluster)
    assert :ok == ControlPlane.subscribe(@store_id, :cluster)
  end

  test "unsubscribe works correctly" do
    :ok = ControlPlane.subscribe(@store_id, :cluster)
    :ok = ControlPlane.unsubscribe(@store_id, :cluster)
    :ok = ControlPlane.publish(@store_id, :cluster, :node_left, %{node: node()})

    refute_received {:control_plane_event, %{event_type: :node_left}}
  end

  test "invalid category returns error" do
    assert {:error, {:invalid_category, :unknown}} = ControlPlane.subscribe(@store_id, :unknown)
  end

  test "statistics reporting" do
    stats = ControlPlane.stats()
    assert %{events_published: 0, events_by_category: %{}, uptime_seconds: _, topics: _} = stats
  end
end
