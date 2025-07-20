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
  require Logger
  
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
      
      Logger.debug("ControlPlane publishing #{event_type} to #{topic}", 
        event: event, topic: topic)
      
      case PubSub.broadcast(ExESDB.PubSub, topic, {:control_plane_event, event}) do
        :ok -> :ok
        error -> 
          Logger.error("Failed to publish control plane event", 
            error: error, event: event, topic: topic)
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
      Logger.debug("ControlPlane subscribing to #{topic}")
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
      Logger.debug("ControlPlane unsubscribing from #{topic}")
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
    Logger.info("ControlPlane starting up as system coordinator")
    
    # Subscribe to our own coordination events
    :ok = subscribe_to_coordination_events(opts)
    
    state = %{
      events_published: 0,
      events_by_category: %{},
      start_time: DateTime.utc_now(),
      opts: opts,
      store_id: Keyword.get(opts, :store_id),
      managed_systems: %{},
      startup_sequence: [:persistence, :notification, :store, :gateway],
      current_startup_step: 0,
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
      current_startup_step: state.current_startup_step
    }
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_cast(:initialize_system, state) do
    Logger.info("ControlPlane: Starting system initialization sequence")
    
    # Publish system initialization started event
    publish(state.store_id, :system, :initialization_started, %{
      sequence: state.startup_sequence,
      node: node()
    })
    
    # Start the first system
    new_state = start_next_system(state)
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_cast({:system_initialized, system_name}, state) do
    Logger.info("ControlPlane: System #{system_name} initialized successfully")
    
    # Update managed systems
    new_managed = Map.put(state.managed_systems, system_name, :running)
    updated_state = %{state | managed_systems: new_managed}
    
    # Publish system started event
    publish(state.store_id, :system, :subsystem_initialized, %{
      system: system_name,
      node: node()
    })
    
    # Start next system if any remaining
    final_state = start_next_system(updated_state)
    {:noreply, final_state}
  end
  
  @impl GenServer
  def handle_cast({:system_failed, system_name, reason}, state) do
    Logger.error("ControlPlane: System #{system_name} failed to initialize: #{inspect(reason)}")
    
    # Publish system failure event
    publish(state.store_id, :system, :subsystem_failed, %{
      system: system_name,
      reason: reason,
      node: node()
    })
    
    # For now, we'll continue with the next system
    # In production, you might want different failure handling strategies
    new_state = start_next_system(state)
    {:noreply, new_state}
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
  
  defp start_next_system(state) do
    if state.current_startup_step < length(state.startup_sequence) do
      system_name = Enum.at(state.startup_sequence, state.current_startup_step)
      Logger.info("ControlPlane: Starting #{system_name} system")
      
      # Attempt to start the system
      case start_system(system_name, state.opts) do
        :ok ->
          # Update state to reflect the system is starting
          new_managed = Map.put(state.managed_systems, system_name, :starting)
          %{state | 
            managed_systems: new_managed,
            current_startup_step: state.current_startup_step + 1
          }
        
        {:error, reason} ->
          Logger.error("ControlPlane: Failed to start #{system_name}: #{inspect(reason)}")
          # Continue with next system despite failure
          %{state | current_startup_step: state.current_startup_step + 1}
      end
    else
      Logger.info("ControlPlane: All systems initialized, system is ready")
      
      # Publish system ready event
      publish(state.store_id, :system, :system_ready, %{
        managed_systems: Map.keys(state.managed_systems),
        node: node()
      })
      
      %{state | system_status: :ready}
    end
  end
  
  defp start_system(system_name, opts) do
    # This is a placeholder implementation
    # In the actual implementation, you would dynamically start supervisors
    # or coordinate with a DynamicSupervisor
    Logger.info("ControlPlane: Would start #{system_name} system with opts: #{inspect(opts)}")
    
    # For now, simulate successful startup
    # In real implementation, this would start actual supervisors
    Process.send_after(self(), {:simulate_system_start, system_name}, 100)
    :ok
  end
  
  defp stop_all_systems(state) do
    # Stop systems in reverse order
    state.managed_systems
    |> Map.keys()
    |> Enum.reverse()
    |> Enum.each(fn system_name ->
      Logger.info("ControlPlane: Stopping #{system_name}")
      # In actual implementation, you would stop the supervisors
      publish(state.store_id, :system, :subsystem_stopping, %{
        system: system_name,
        node: node()
      })
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
