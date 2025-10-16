defmodule ExESDB.SubscriptionHealthTracker do
  @moduledoc """
  Centralized tracker for subscription health events received via :ex_esdb_system PubSub.
  
  This module:
  - Subscribes to subscription health events from subscription proxies
  - Maintains current health status for all subscriptions in a store
  - Provides APIs to query subscription health
  - Publishes aggregated health summaries
  - Integrates with the broader ExESDB monitoring system
  """
  
  use GenServer
  
  alias ExESDB.StoreNaming
  alias ExESDB.Themes, as: Themes
  require Logger
  
  @health_table_prefix :subscription_health_
  @health_summary_interval :timer.seconds(30)
  
  # Health status types
  @type health_status :: :healthy | :degraded | :failed | :registering | :unknown
  
  @type health_event :: %{
    store_id: atom(),
    subscription_name: String.t(),
    event_type: atom(),
    metadata: map()
  }
  
  @type health_data :: %{
    subscription_name: String.t(),
    current_status: health_status(),
    last_seen: integer(),
    event_count: non_neg_integer(),
    last_event: health_event(),
    error_count: non_neg_integer(),
    last_error: term() | nil
  }
  
  ## Public API
  
  @doc """
  Gets the current health status for all subscriptions in a store.
  """
  @spec get_store_health_summary(atom()) :: {:ok, map()} | {:error, term()}
  def get_store_health_summary(store_id) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, :get_health_summary)
  end
  
  @doc """
  Gets detailed health information for a specific subscription.
  """
  @spec get_subscription_health(atom(), String.t()) :: {:ok, health_data()} | {:error, :not_found}
  def get_subscription_health(store_id, subscription_name) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, {:get_subscription_health, subscription_name})
  end
  
  @doc """
  Lists all subscriptions currently being tracked.
  """
  @spec list_tracked_subscriptions(atom()) :: {:ok, [String.t()]}
  def list_tracked_subscriptions(store_id) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, :list_subscriptions)
  end
  
  ## GenServer Implementation
  
  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  @impl GenServer
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    # Create ETS table for fast health lookups
    table_name = String.to_atom("#{@health_table_prefix}#{store_id}")
    :ets.new(table_name, [:named_table, :public, :set])
    
    # Subscribe to all subscription health events for this store using dedicated health PubSub
    store_topic = "store_health:#{store_id}"
    _subscription_topic_pattern = "subscription_health:#{store_id}:*"
    
    :ok = Phoenix.PubSub.subscribe(:ex_esdb_health, store_topic)
    # Note: PubSub doesn't support wildcard subscriptions, so we'll need to handle this differently
    # We'll subscribe to events as subscriptions are discovered
    
    # Schedule periodic health summary publishing
    Process.send_after(self(), :publish_health_summary, @health_summary_interval)
    
    state = %{
      store_id: store_id,
      health_table: table_name,
      subscribed_topics: MapSet.new([store_topic]),
      last_summary_published: System.system_time(:millisecond)
    }
    
    Logger.info("#{Themes.subscription_health_tracker(self(), "Started for store: #{store_id}")}")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_info({:subscription_health, health_event}, state) do
    updated_state = process_health_event(state, health_event)
    {:noreply, updated_state}
  end
  
  @impl GenServer
  def handle_info(:publish_health_summary, state) do
    publish_health_summary(state)
    
    # Schedule next summary
    Process.send_after(self(), :publish_health_summary, @health_summary_interval)
    
    updated_state = %{state | last_summary_published: System.system_time(:millisecond)}
    {:noreply, updated_state}
  end
  
  @impl GenServer
  def handle_call(:get_health_summary, _from, state) do
    summary = build_health_summary(state)
    {:reply, {:ok, summary}, state}
  end
  
  @impl GenServer
  def handle_call({:get_subscription_health, subscription_name}, _from, state) do
    case :ets.lookup(state.health_table, subscription_name) do
      [{^subscription_name, health_data}] -> {:reply, {:ok, health_data}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions = 
      :ets.tab2list(state.health_table)
      |> Enum.map(fn {subscription_name, _} -> subscription_name end)
      
    {:reply, {:ok, subscriptions}, state}
  end
  
  ## Private Functions
  
  defp process_health_event(state, health_event) do
    %{
      store_id: store_id,
      subscription_name: subscription_name,
      event_type: event_type,
      metadata: metadata
    } = health_event
    
    # Ensure we're subscribed to this subscription's health events
    updated_state = ensure_subscription_topic(state, store_id, subscription_name)
    
    # Update health data
    now = System.system_time(:millisecond)
    current_health = get_current_health_data(updated_state.health_table, subscription_name)
    
    updated_health = update_health_data(current_health, event_type, health_event, now)
    
    # Store updated health data
    :ets.insert(updated_state.health_table, {subscription_name, updated_health})
    
    # Log significant health changes
    log_health_change(event_type, subscription_name, metadata)
    
    updated_state
  end
  
  defp ensure_subscription_topic(state, store_id, subscription_name) do
    topic = "subscription_health:#{store_id}:#{subscription_name}"
    
    if MapSet.member?(state.subscribed_topics, topic) do
      state
    else
      :ok = Phoenix.PubSub.subscribe(:ex_esdb_health, topic)
      %{state | subscribed_topics: MapSet.put(state.subscribed_topics, topic)}
    end
  end
  
  defp get_current_health_data(table, subscription_name) do
    case :ets.lookup(table, subscription_name) do
      [{^subscription_name, health_data}] -> health_data
      [] -> %{
        subscription_name: subscription_name,
        current_status: :unknown,
        last_seen: 0,
        event_count: 0,
        last_event: nil,
        error_count: 0,
        last_error: nil
      }
    end
  end
  
  defp update_health_data(current_health, event_type, health_event, now) do
    new_status = determine_health_status(event_type, health_event)
    is_error = is_error_event?(event_type)
    
    %{
      current_health |
      current_status: new_status,
      last_seen: now,
      event_count: current_health.event_count + 1,
      last_event: health_event,
      error_count: if(is_error, do: current_health.error_count + 1, else: current_health.error_count),
      last_error: if(is_error, do: health_event, else: current_health.last_error)
    }
  end
  
  defp determine_health_status(:registration_started, _), do: :registering
  defp determine_health_status(:registration_success, _), do: :healthy
  defp determine_health_status(:registration_failed, _), do: :failed
  defp determine_health_status(:proxy_started, _), do: :healthy
  defp determine_health_status(:proxy_stopped, _), do: :failed
  defp determine_health_status(:proxy_crashed, _), do: :failed
  defp determine_health_status(:circuit_breaker_opened, _), do: :degraded
  defp determine_health_status(:circuit_breaker_closed, _), do: :healthy  
  defp determine_health_status(:event_delivery_success, _), do: :healthy
  defp determine_health_status(:event_delivery_failed, _), do: :degraded
  defp determine_health_status(:periodic_heartbeat, _), do: :healthy
  defp determine_health_status(_, _), do: :unknown
  
  defp is_error_event?(event_type) do
    event_type in [:registration_failed, :proxy_crashed, :circuit_breaker_opened, :event_delivery_failed]
  end
  
  defp log_health_change(:registration_failed, subscription_name, metadata) do
    error = Map.get(metadata, :error, "unknown")
    Logger.warning("Subscription #{subscription_name} registration failed: #{inspect(error)}")
  end
  
  defp log_health_change(:proxy_crashed, subscription_name, metadata) do
    reason = Map.get(metadata, :crash_reason, "unknown")
    Logger.error("Subscription #{subscription_name} proxy crashed: #{inspect(reason)}")
  end
  
  defp log_health_change(:circuit_breaker_opened, subscription_name, metadata) do
    reason = Map.get(metadata, :reason, "unknown")
    Logger.warning("Circuit breaker opened for subscription #{subscription_name}: #{inspect(reason)}")
  end
  
  defp log_health_change(_, _, _), do: :ok
  
  defp build_health_summary(state) do
    all_health_data = :ets.tab2list(state.health_table)
    
    summary = Enum.reduce(all_health_data, %{
      total_subscriptions: 0,
      healthy: 0,
      degraded: 0, 
      failed: 0,
      registering: 0,
      unknown: 0
    }, fn {_name, health_data}, acc ->
      status = health_data.current_status
      %{
        acc |
        total_subscriptions: acc.total_subscriptions + 1,
        healthy: acc.healthy + (if status == :healthy, do: 1, else: 0),
        degraded: acc.degraded + (if status == :degraded, do: 1, else: 0),
        failed: acc.failed + (if status == :failed, do: 1, else: 0),
        registering: acc.registering + (if status == :registering, do: 1, else: 0),
        unknown: acc.unknown + (if status == :unknown, do: 1, else: 0)
      }
    end)
    
    Map.put(summary, :store_id, state.store_id)
  end
  
  defp publish_health_summary(state) do
    summary = build_health_summary(state)
    
    topic = "health_summary:#{state.store_id}"
    Phoenix.PubSub.broadcast(:ex_esdb_health, topic, {:health_summary, summary})
    
    Logger.debug("Published health summary for store #{state.store_id}: #{inspect(summary)}")
  end
end
