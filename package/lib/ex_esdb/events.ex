defmodule ExESDB.Events do
  @moduledoc """
  Event definitions and schemas for ExESDB subsystems.

  This module provides centralized event type definitions and helper functions
  for building event payloads. Each module is responsible for publishing its
  own events using Phoenix.PubSub directly.

  ## Event Categories

  - `:system` - System lifecycle and initialization events
  - `:cluster` - Cluster membership and coordination events
  - `:leadership` - Leadership changes and responsibilities
  - `:persistence` - Data persistence and storage events
  - `:gateway` - External interface and API events
  - `:coordination` - General coordination events
  - `:subscriptions` - Subscription management events

  ## Usage

  ```elixir
  # Each module publishes its own events:

  # In PersistenceWorker:
  event = Events.build_event(:events_persisted, %{stream_id: "orders", event_count: 5})
  Phoenix.PubSub.broadcast(ExESDB.PubSub, "exesdb:control:store_id:persistence", 
    {:persistence_event, event})

  # In StoreCluster:
  event = Events.build_event(:cluster_joined, %{via_node: target_node})
  Phoenix.PubSub.broadcast(ExESDB.PubSub, "exesdb:control:store_id:cluster", 
    {:cluster_event, event})
  ```
  """

  ## Event Type Definitions

  @system_events [
    :system_startup_initiated,
    :subsystem_starting,
    :subsystem_ready,
    :subsystem_failed,
    :control_plane_starting,
    :initialization_started,
    :system_ready,
    :systems_pending,
    :subsystem_stopping
  ]

  @cluster_events [
    :cluster_join_attempted,
    :cluster_joined,
    :cluster_join_failed,
    :node_discovered,
    :node_failure_detected,
    :cluster_membership_changed,
    :coordinator_not_available,
    :single_node_mode,
    :unknown_db_type,
    :no_connected_nodes,
    :attempting_direct_join,
    :no_existing_cluster_found,
    :cluster_joined_successfully,
    :cluster_left,
    :cluster_leave_failed
  ]

  @leadership_events [
    :leadership_assumed,
    :leadership_lost,
    :khepri_leader_changed,
    :leader_lookup_failed,
    :activating_leader_worker,
    :leader_worker_activated,
    :leader_worker_activation_failed,
    :leader_detected,
    :leadership_change,
    :leadership_lost_event
  ]

  @persistence_events [
    :persistence_worker_started,
    :events_persisted,
    :persistence_write_started,
    :persistence_error,
    :persistence_requested,
    :persistence_completed,
    :persistence_failed
  ]

  @gateway_events [
    :gateway_worker_started,
    :gateway_worker_terminated,
    :stream_write_requested,
    :registration_failed,
    :gateway_worker_registered,
    :gateway_worker_unregistered
  ]

  @coordination_events [
    :coordinator_elected,
    :coordinator_waiting,
    :cluster_verification_success,
    :cluster_verification_warning,
    :event_published,
    :event_publication_failed,
    :subscription_started,
    :subscription_ended
  ]

  @subscription_events [
    :subscription_created,
    :subscription_updated,
    :subscription_deleted,
    :emitter_pool_started,
    :emitter_pool_stopped,
    :emitter_pool_failed,
    :subscription_registered,
    :subscription_unregistered
  ]

  ## Public API

  @doc "Returns all defined system events"
  def system_events, do: @system_events

  @doc "Returns all defined cluster events"
  def cluster_events, do: @cluster_events

  @doc "Returns all defined leadership events"
  def leadership_events, do: @leadership_events

  @doc "Returns all defined persistence events"
  def persistence_events, do: @persistence_events

  @doc "Returns all defined gateway events"
  def gateway_events, do: @gateway_events

  @doc "Returns all defined coordination events"
  def coordination_events, do: @coordination_events

  @doc "Returns all defined subscription events"
  def subscription_events, do: @subscription_events

  @doc "Returns all event types organized by category"
  def all_events do
    %{
      system: @system_events,
      cluster: @cluster_events,
      leadership: @leadership_events,
      persistence: @persistence_events,
      gateway: @gateway_events,
      coordination: @coordination_events,
      subscriptions: @subscription_events
    }
  end

  @doc "Checks if an event type is valid for a given category"
  def valid_event?(category, event_type) when is_atom(category) and is_atom(event_type) do
    case category do
      :system -> event_type in @system_events
      :cluster -> event_type in @cluster_events
      :leadership -> event_type in @leadership_events
      :persistence -> event_type in @persistence_events
      :gateway -> event_type in @gateway_events
      :coordination -> event_type in @coordination_events
      :subscriptions -> event_type in @subscription_events
      _ -> false
    end
  end

  ## Event Builder Helpers

  @doc """
  Builds a standard event map with common fields.

  ## Parameters
  - `event_type` - The event type (atom)
  - `data` - Event-specific data (map)
  - `opts` - Optional fields like `:store_id` (keyword list)

  ## Examples
      Events.build_event(:cluster_joined, %{via_node: node1})
      Events.build_event(:events_persisted, %{stream_id: "orders", count: 5}, store_id: :my_store)
  """
  def build_event(event_type, data \\ %{}, opts \\ [])
      when is_atom(event_type) and is_map(data) do
    %{
      event_id: generate_event_id(),
      event_type: event_type,
      store_id: Keyword.get(opts, :store_id),
      node: node(),
      timestamp: DateTime.utc_now(),
      data: data
    }
  end

  @doc """
  Builds a topic string for a given store and category.

  ## Examples
      Events.build_topic(:my_store, :cluster)
      # => "exesdb:control:my_store:cluster"
  """
  def build_topic(store_id, category) when is_atom(store_id) and is_atom(category) do
    "exesdb:control:#{store_id}:#{category}"
  end

  @doc """
  Helper to build event payload with standardized event wrapper.

  ## Examples
      Events.build_payload(:cluster_event, :cluster_joined, %{via_node: node1})
      # => {:cluster_event, %{event_type: :cluster_joined, ...}}
  """
  def build_payload(event_wrapper, event_type, data \\ %{}, opts \\ []) do
    event = build_event(event_type, data, opts)
    {event_wrapper, event}
  end

  ## Private Helpers

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  ## Event Schema Validation

  @doc "Validates that an event has all required fields"
  def valid_event_structure?(event) when is_map(event) do
    required_fields = [:event_id, :event_type, :node, :timestamp]
    Enum.all?(required_fields, &Map.has_key?(event, &1))
  end

  def valid_event_structure?(_), do: false
end
