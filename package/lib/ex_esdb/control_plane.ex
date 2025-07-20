defmodule ExESDB.ControlPlane do
  @moduledoc """
  Control Plane for ExESDB - Event-driven coordination system.
  
  This module provides a centralized event-driven coordination layer for ExESDB components.
  It uses Phoenix.PubSub to decouple component interactions and provides better observability,
  fault tolerance, and testability.
  
  ## Topics Structure
  
  - `exesdb:control:{store_id}:cluster` - Cluster membership and node coordination
  - `exesdb:control:{store_id}:leadership` - Leadership election and changes
  - `exesdb:control:{store_id}:subscriptions` - Subscription lifecycle events
  - `exesdb:control:{store_id}:coordination` - General coordination events
  - `exesdb:control:{store_id}:system` - System lifecycle events
  
  ## Event Types
  
  Each event is a map with the following structure:
  ```elixir
  %{
    event_id: unique_id,
    event_type: atom,
    store_id: atom,
    node: node(),
    timestamp: DateTime.utc_now(),
    data: %{...}
  }
  ```
  
  ## Usage
  
  ```elixir
  # Publish an event
  ControlPlane.publish(store_id, :cluster, :node_joined, %{node: node()})
  
  # Subscribe to events
  ControlPlane.subscribe(store_id, :cluster)
  
  # Handle events in your GenServer
  def handle_info({:control_plane_event, event}, state) do
    # Process the event
    {:noreply, state}
  end
  ```
  """
  use GenServer
  
  alias Phoenix.PubSub
  
  @type store_id :: atom()
  @type topic_category :: :cluster | :leadership | :subscriptions | :coordination | :system
  @type event_type :: atom()
  @type event_data :: map()
  @type control_event :: %{
    event_id: String.t(),
    event_type: event_type(),
    store_id: store_id(),
    node: node(),
    timestamp: DateTime.t(),
    data: event_data()
  }
  
  # Topic categories and their purposes
  @topic_categories %{
    cluster: "Cluster membership and node coordination",
    leadership: "Leadership election and changes", 
    subscriptions: "Subscription lifecycle events",
    coordination: "General coordination events",
    system: "System lifecycle events"
  }
  
  ## Public API
  
  @doc """
  Publishes an event to the control plane.
  
  ## Parameters
  - `store_id` - The store identifier
  - `category` - The topic category (:cluster, :leadership, etc.)
  - `event_type` - The specific event type (atom)
  - `data` - Event-specific data (map)
  
  ## Examples
      ControlPlane.publish(:my_store, :cluster, :node_joined, %{node: node()})
      ControlPlane.publish(:my_store, :leadership, :leader_elected, %{leader: node()})
  """
  @spec publish(store_id(), topic_category(), event_type(), event_data()) :: :ok | {:error, term()}
  def publish(store_id, category, event_type, data \\ %{}) do
    if valid_category?(category) do
      event = build_event(store_id, event_type, data)
      topic = build_topic(store_id, category)
      
      case PubSub.broadcast(ExESDB.PubSub, topic, {:control_plane_event, event}) do
        :ok -> :ok
        error -> 
          # Don't log here as it would cause recursion - let caller handle
          error
      end
    else
      {:error, {:invalid_category, category}}
    end
  end
  
  @doc """
  Subscribes the current process to control plane events for a specific category.
  
  ## Parameters
  - `store_id` - The store identifier
  - `category` - The topic category to subscribe to
  
  ## Examples
      ControlPlane.subscribe(:my_store, :cluster)
      ControlPlane.subscribe(:my_store, :leadership)
  """
  @spec subscribe(store_id(), topic_category()) :: :ok | {:error, term()}
  def subscribe(store_id, category) do
    if valid_category?(category) do
      topic = build_topic(store_id, category)
      # Subscription successful - no logging needed
      PubSub.subscribe(ExESDB.PubSub, topic)
    else
      {:error, {:invalid_category, category}}
    end
  end
  
  @doc """
  Unsubscribes the current process from control plane events.
  """
  @spec unsubscribe(store_id(), topic_category()) :: :ok | {:error, term()}
  def unsubscribe(store_id, category) do
    if valid_category?(category) do
      topic = build_topic(store_id, category)
      # Unsubscription successful - no logging needed
      PubSub.unsubscribe(ExESDB.PubSub, topic)
    else
      {:error, {:invalid_category, category}}
    end
  end
  
  @doc """
  Lists all subscribers for a specific topic.
  Useful for debugging and monitoring.
  
  Note: This function is not implemented as Phoenix.PubSub doesn't expose
  subscriber lists. This is intentional for privacy and performance reasons.
  """
  @spec list_subscribers(store_id(), topic_category()) :: {:error, :not_supported}
  def list_subscribers(_store_id, _category) do
    {:error, :not_supported}
  end
  
  @doc """
  Gets information about available topic categories.
  """
  @spec topic_categories() :: map()
  def topic_categories, do: @topic_categories
  
  ## GenServer Implementation
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    store_id = Keyword.get(opts, :store_id)
    PubSub.broadcast(ExESDB.PubSub, "exesdb:control:#{store_id}:system", {:control_plane_event, %{event_type: :control_plane_starting, node: node()}})
    
    # Subscribe to our own coordination events
    :ok = subscribe_to_coordination_events(opts)
    
    state = %{
      events_published: 0,
      events_by_category: %{},
      start_time: DateTime.utc_now(),
      opts: opts,
      store_id: Keyword.get(opts, :store_id),
      managed_systems: %{},
      expected_systems: [:persistence, :notification, :store, :cluster, :gateway],
      ready_systems: MapSet.new(),
      system_status: :initializing
    }
    
    # Start the system initialization sequence
    GenServer.cast(self(), :initialize_system)
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      events_published: state.events_published,
      events_by_category: state.events_by_category,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.start_time),
      topics: get_active_topics(),
      managed_systems: state.managed_systems,
      system_status: state.system_status,
      expected_systems: state.expected_systems,
      ready_systems: MapSet.to_list(state.ready_systems),
      systems_ready_count: MapSet.size(state.ready_systems)
    }
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_cast(:initialize_system, state) do
    # Event published by :initialize_system cast above
    
    # Publish system initialization started event
    # Systems should start in parallel and report back when ready
    PubSub.broadcast(ExESDB.PubSub, "exesdb:control:#{state.store_id}:system", {:control_plane_event, %{event_type: :initialization_started, expected_systems: state.expected_systems, node: node()}})
    
    {:noreply, %{state | system_status: :waiting_for_systems}}
  end
  
  
  @impl GenServer
  def handle_info({:control_plane_event, %{event_type: :subsystem_ready, data: %{system: system_name}} = event}, state) do
    # System readiness handled via event
    
    # Add system to ready systems
    new_ready_systems = MapSet.put(state.ready_systems, system_name)
    new_managed_systems = Map.put(state.managed_systems, system_name, :ready)
    
    updated_state = %{
      state | 
      ready_systems: new_ready_systems,
      managed_systems: new_managed_systems,
      events_published: state.events_published + 1,
      events_by_category: Map.update(state.events_by_category, event.event_type, 1, &(&1 + 1))
    }
    
    # Check if all expected systems are ready
    final_state = check_system_readiness(updated_state)
    {:noreply, final_state}
  end
  
  @impl GenServer
  def handle_info({:control_plane_event, %{event_type: :subsystem_starting, data: %{system: system_name}} = event}, state) do
    # System starting handled via event
    
    new_managed_systems = Map.put(state.managed_systems, system_name, :starting)
    
    updated_state = %{
      state | 
      managed_systems: new_managed_systems,
      events_published: state.events_published + 1,
      events_by_category: Map.update(state.events_by_category, event.event_type, 1, &(&1 + 1))
    }
    
    {:noreply, updated_state}
  end
  
  @impl GenServer
  def handle_info({:control_plane_event, %{event_type: :subsystem_failed, data: %{system: system_name}} = event}, state) do
    # System failure handled via event
    
    new_managed_systems = Map.put(state.managed_systems, system_name, :failed)
    
    updated_state = %{
      state | 
      managed_systems: new_managed_systems,
      events_published: state.events_published + 1,
      events_by_category: Map.update(state.events_by_category, event.event_type, 1, &(&1 + 1))
    }
    
    {:noreply, updated_state}
  end
  
  @impl GenServer
  def handle_info({:control_plane_event, event}, state) do
    # Track our own events for statistics
    new_state = %{
      state | 
      events_published: state.events_published + 1,
      events_by_category: Map.update(state.events_by_category, 
        event.event_type, 1, &(&1 + 1))
    }
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_info({:simulate_system_start, system_name}, state) do
    # Simulate successful system initialization
    GenServer.cast(self(), {:system_initialized, system_name})
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp build_event(store_id, event_type, data) do
    %{
      event_id: generate_event_id(),
      event_type: event_type,
      store_id: store_id,
      node: node(),
      timestamp: DateTime.utc_now(),
      data: data
    }
  end
  
  defp build_topic(store_id, category) do
    "exesdb:control:#{store_id}:#{category}"
  end
  
  defp valid_category?(category) do
    Map.has_key?(@topic_categories, category)
  end
  
  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp get_active_topics do
    # This would ideally query Phoenix.PubSub for active topics
    # For now, we'll return the topic categories
    Map.keys(@topic_categories)
  end
  
  defp subscribe_to_coordination_events(opts) do
    store_id = Keyword.get(opts, :store_id)
    # Subscribe to system coordination events to monitor system lifecycle
    :ok = subscribe(store_id, :system)
    :ok = subscribe(store_id, :coordination)
  end
  
  
  defp check_system_readiness(state) do
    expected_set = MapSet.new(state.expected_systems)
    
    if MapSet.equal?(state.ready_systems, expected_set) do
      # All systems ready - publish system_ready event below
      
      # Publish system ready event
      PubSub.broadcast(ExESDB.PubSub, "exesdb:control:#{state.store_id}:system", {:control_plane_event, %{event_type: :system_ready, ready_systems: MapSet.to_list(state.ready_systems), node: node()}})
      
      %{state | system_status: :ready}
    else
      missing_systems = MapSet.difference(expected_set, state.ready_systems)
      # Still waiting for systems - publish waiting event
      PubSub.broadcast(ExESDB.PubSub, "exesdb:control:#{state.store_id}:system", {:control_plane_event, %{event_type: :systems_pending, missing_systems: MapSet.to_list(missing_systems), ready_systems: MapSet.to_list(state.ready_systems)}})
      state
    end
  end
  
  defp stop_all_systems(state) do
    # Stop systems in reverse order
    state.managed_systems
    |> Map.keys()
    |> Enum.reverse()
    |> Enum.each(fn system_name ->
      # Publish system stopping event
      # In actual implementation, you would stop the supervisors
      PubSub.broadcast(ExESDB.PubSub, "exesdb:control:#{state.store_id}:system", {:control_plane_event, %{event_type: :subsystem_stopping, system: system_name, node: node()}})
    end)
  end
  
  ## Stats API
  
  @doc """
  Gets statistics about the control plane.
  """
  def stats do
    try do
      GenServer.call(__MODULE__, :stats, 5000)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, {:noproc, _} -> {:error, :not_started}
    end
  end
  
  ## Child Spec
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end
end
