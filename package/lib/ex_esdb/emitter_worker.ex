defmodule ExESDB.EmitterWorker do
  @moduledoc """
    As part of the ExESDB.System, 
    the EmitterWorker is responsible for managing the communication 
    between the Event Store and the PubSub mechanism.
  """
  use GenServer

  alias Phoenix.PubSub, as: PubSub
  alias ExESDB.LoggingPublisher
  alias ExESDB.PubSubIntegration

  require Logger

  defp send_or_kill_pool(pid, event, store, selector) do
    if Process.alive?(pid) do
      Process.send(pid, {:events, [event]}, [])
    else
      ExESDB.EmitterPool.stop(store, selector)
    end
  end

  # Always emit events to :ex_esdb_events if the emitter is active
  defp emit(_pub_sub, topic, event) do
    if Process.get(:emitter_active) do
      :ex_esdb_events
      |> PubSub.broadcast(topic, {:events, [event]})
    else
      {:error, :not_active}
    end
  end

  @impl GenServer
  def init({store, sub_topic, subscriber}) do
    Process.flag(:trap_exit, true)
    scheduler_id = :erlang.system_info(:scheduler_id)
    topic = :emitter_group.topic(store, sub_topic)

    :ok = :emitter_group.join(store, sub_topic, self())
    Process.put(:emitter_active, true)
    
    # Subscribe to health events for subscriptions related to this emitter
    subscribe_to_health_events(store, sub_topic)

    # Publish startup event instead of direct terminal output
    LoggingPublisher.startup(
      :emitter_worker,
      store,
      "EMITTER WORKER ACTIVATION",
      %{
        topic: topic,
        subscriber: subscriber,
        scheduler_id: scheduler_id
      }
    )
    
    # Broadcast emitter worker lifecycle event
    PubSubIntegration.broadcast_lifecycle_event(
      :emitter_worker_started,
      self(),
      %{
        store: store,
        sub_topic: sub_topic,
        topic: topic,
        scheduler_id: scheduler_id
      }
    )
    
    # Broadcast store-specific component health
    PubSubIntegration.broadcast_store_health(
      store,
      :emitter_worker,
      :healthy,
      %{
        sub_topic: sub_topic,
        topic: topic,
        event: :started
      }
    )

    {:ok, %{
      subscriber: subscriber, 
      store: store, 
      selector: sub_topic,
      health_status: :unknown,
      subscription_healthy: true
    }}
  end

  @impl GenServer
  def terminate(reason, %{store: store, selector: selector, subscriber: subscriber}) do
    # Mark process as inactive to prevent further broadcasts
    Process.put(:emitter_active, false)

    # Publish shutdown event instead of direct terminal output
    LoggingPublisher.shutdown(
      :emitter_worker,
      store,
      "EMITTER WORKER TERMINATION",
      %{
        reason: reason,
        selector: selector,
        subscriber: subscriber
      }
    )
    
    # Broadcast emitter worker termination lifecycle event
    PubSubIntegration.broadcast_lifecycle_event(
      :emitter_worker_terminated,
      self(),
      %{
        store: store,
        selector: selector,
        reason: reason
      }
    )
    
    # Broadcast store-specific component health update
    PubSubIntegration.broadcast_store_health(
      store,
      :emitter_worker,
      :unhealthy,
      %{
        selector: selector,
        event: :terminated,
        reason: reason
      }
    )

    # Leave the emitter group and cleanup
    :ok = :emitter_group.leave(store, selector, self())
    :ok
  end

  def start_link({store, sub_topic, subscriber, emitter}),
    do:
      GenServer.start_link(
        __MODULE__,
        {store, sub_topic, subscriber},
        name: emitter
      )

  def child_spec({store, sub_topic, subscriber, emitter}) do
    %{
      id: Module.concat(__MODULE__, emitter),
      start: {__MODULE__, :start_link, [{store, sub_topic, subscriber, emitter}]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @impl true
  def handle_info(
        {:broadcast, topic, event},
        %{subscriber: subscriber, store: store, selector: selector} = state
      ) do
    # Publish action event instead of direct terminal output
    event_id = Map.get(event, :event_id, "unknown")
    event_type = Map.get(event, :event_type, "unknown")

    LoggingPublisher.action(
      :emitter_worker,
      store,
      "⚡ BROADCASTING Event: #{event_id}(#{event_type}) - Topic: #{topic}",
      %{event_id: event_id, event_type: event_type, topic: topic}
    )

  case subscriber do
      nil ->
        emit(nil, topic, event)
      pid ->
        send_or_kill_pool(pid, event, store, selector)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:forward_to_local, topic, event},
        %{subscriber: subscriber, store: store, selector: selector} = state
      ) do
    # Publish action event instead of direct terminal output
    event_id = Map.get(event, :event_id, "unknown")
    event_type = Map.get(event, :event_type, "unknown")

    LoggingPublisher.action(
      :emitter_worker,
      store,
      "🔄 FORWARDING Event: #{event_id}(#{event_type}) - Local Topic: #{topic}",
      %{event_id: event_id, event_type: event_type, topic: topic}
    )

  case subscriber do
      nil ->
        emit(nil, topic, event)
      pid ->
        send_or_kill_pool(pid, event, store, selector)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:events, events}, state) when is_list(events) do
    # Handle events messages - these might come from feedback loops or external systems
    # Just ignore them since they're already processed events
    {:noreply, state}
  end

  # Handle subscription health events
  @impl true
  def handle_info({:subscription_health, health_event}, state) do
    # Log the received health event
    %{
      subscription_name: subscription_name,
      event_type: event_type,
      metadata: metadata
    } = health_event
    
    LoggingPublisher.health(
      :emitter_worker,
      state.store,
      "📡 HEALTH EVENT: #{subscription_name} - #{event_type}",
      %{subscription_name: subscription_name, event_type: event_type, metadata: metadata}
    )
    
    updated_state = process_health_event(state, health_event)
    {:noreply, updated_state}
  end

  # Handle health summary events
  @impl true
  def handle_info({:health_summary, summary_data}, state) do
    # Log the received health summary
    store = Map.get(summary_data, :store, "unknown")
    healthy_count = Map.get(summary_data, :healthy_subscriptions, 0)
    unhealthy_count = Map.get(summary_data, :unhealthy_subscriptions, 0)
    total_count = healthy_count + unhealthy_count
    
    LoggingPublisher.health(
      :emitter_worker,
      state.store,
      "📈 HEALTH SUMMARY: Store #{store} - #{healthy_count}/#{total_count} healthy subscriptions",
      %{healthy_count: healthy_count, unhealthy_count: unhealthy_count, total_count: total_count}
    )
    
    {:noreply, state}
  end

  # Handle store metrics events
  @impl true
  def handle_info({:store_metrics, metrics_event}, state) do
    # Log the received metrics event
    metric_name = Map.get(metrics_event, :metric_name, "unknown")
    metric_value = Map.get(metrics_event, :value, "N/A")
    store_id = Map.get(metrics_event, :store_id, "unknown")
    timestamp = Map.get(metrics_event, :timestamp, "unknown")
    
    LoggingPublisher.action(
      :emitter_worker,
      state.store,
      "📈 METRICS EVENT: #{store_id} -> #{metric_name}=#{metric_value} @#{timestamp}",
      %{metric_name: metric_name, metric_value: metric_value, store_id: store_id, timestamp: timestamp}
    )
    
    {:noreply, state}
  end

  # Handle metrics summary events
  @impl true
  def handle_info({:metrics_summary, summary_data}, state) do
    # Log the received metrics summary
    store = Map.get(summary_data, :store, "unknown")
    events_per_sec = Map.get(summary_data, :events_per_second, 0)
    total_events = Map.get(summary_data, :total_events, 0)
    active_subscriptions = Map.get(summary_data, :active_subscriptions, 0)
    
    LoggingPublisher.action(
      :emitter_worker,
      state.store,
      "📉 METRICS SUMMARY: Store #{store} - #{events_per_sec} eps, #{total_events} total, #{active_subscriptions} active subs",
      %{events_per_sec: events_per_sec, total_events: total_events, active_subscriptions: active_subscriptions}
    )
    
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Received unexpected message #{inspect(msg)} on #{inspect(self())}")

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:update_subscriber, new_subscriber}, state) do
    updated_state = %{state | subscriber: new_subscriber}
    {:noreply, updated_state}
  end
  
  # Private health-related functions
  
  defp subscribe_to_health_events(store, _sub_topic) do
    # Subscribe to store-wide health events using the dedicated health PubSub
    store_health_topic = "store_health:#{store}"
    :ok = Phoenix.PubSub.subscribe(:ex_esdb_health, store_health_topic)
    
    # Subscribe to health summary updates
    health_summary_topic = "health_summary:#{store}"
    :ok = Phoenix.PubSub.subscribe(:ex_esdb_health, health_summary_topic)
    
    # Subscribe to metrics events using the system PubSub
    store_metrics_topic = "store_metrics:#{store}"
    :ok = Phoenix.PubSub.subscribe(:ex_esdb_system, store_metrics_topic)
    
    # Subscribe to metrics summary updates
    metrics_summary_topic = "metrics_summary:#{store}"
    :ok = Phoenix.PubSub.subscribe(:ex_esdb_system, metrics_summary_topic)
    
    LoggingPublisher.action(
      :emitter_worker,
      store,
      "🩺 SUBSCRIBED to health events for store: #{store}",
      %{health_topics: [store_health_topic, health_summary_topic]}
    )
    
    LoggingPublisher.action(
      :emitter_worker,
      store,
      "📈 SUBSCRIBED to metrics events for store: #{store}",
      %{metrics_topics: [store_metrics_topic, metrics_summary_topic]}
    )
  end
  
  defp process_health_event(state, health_event) do
    %{
      subscription_name: subscription_name,
      event_type: event_type,
      metadata: _metadata
    } = health_event
    
    # Determine if this health event affects our emission behavior
    new_health_status = determine_health_impact(event_type)
    subscription_healthy = is_subscription_healthy?(new_health_status)
    
    # Log significant health changes that affect emission
    if state.subscription_healthy != subscription_healthy do
      log_health_impact(state.store, subscription_name, event_type, subscription_healthy)
      
      # Potentially pause/resume emission based on health
      update_emission_state(subscription_healthy)
    end
    
    %{
      state |
      health_status: new_health_status,
      subscription_healthy: subscription_healthy
    }
  end
  
  defp determine_health_impact(:registration_failed), do: :failed
  defp determine_health_impact(:proxy_crashed), do: :failed
  defp determine_health_impact(:circuit_breaker_opened), do: :degraded
  defp determine_health_impact(:registration_success), do: :healthy
  defp determine_health_impact(:circuit_breaker_closed), do: :healthy
  defp determine_health_impact(:event_delivery_success), do: :healthy
  defp determine_health_impact(_), do: :unknown
  
  defp is_subscription_healthy?(health_status) do
    health_status in [:healthy, :unknown]
  end
  
  defp log_health_impact(store, subscription_name, event_type, healthy) do
    status_msg = if healthy, do: "HEALTHY", else: "UNHEALTHY"
    LoggingPublisher.health(
      :emitter_worker,
      store,
      "🏥 HEALTH IMPACT: #{subscription_name} is #{status_msg} (#{event_type})",
      %{subscription_name: subscription_name, event_type: event_type, healthy: healthy}
    )
  end
  
  defp update_emission_state(healthy) do
    # For now, we keep emitting regardless of health status
    # but we could implement more sophisticated logic here:
    # - Pause emission for failed subscriptions
    # - Throttle emission for degraded subscriptions
    # - Resume normal emission for healthy subscriptions
    
    Process.put(:emitter_active, healthy)
    
    if healthy do
      Logger.debug("Emission RESUMED due to healthy status")
    else
      Logger.warning("Emission PAUSED due to unhealthy status")
    end
  end
end
