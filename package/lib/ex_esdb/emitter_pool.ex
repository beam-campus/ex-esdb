defmodule ExESDB.EmitterPool do
  @moduledoc false
  use Supervisor

  require Logger
  alias ExESDB.LoggingPublisher
  alias ExESDB.PubSubIntegration

  def name(store, sub_topic),
    do: :"#{store}:#{sub_topic}_emitter_pool"

  def start_link({store, sub_topic, subscriber, pool_size, filter}) do
    Supervisor.start_link(
      __MODULE__,
      {store, sub_topic, subscriber, pool_size, filter},
      name: name(store, sub_topic)
    )
  end

  @impl Supervisor
  def init({store, sub_topic, subscriber, pool_size, filter}) do
    emitter_names =
      store
      |> :emitter_group.setup_emitter_mechanism(sub_topic, filter, pool_size)

    children =
      for emitter <- emitter_names do
        Supervisor.child_spec(
          {ExESDB.EmitterWorker, {store, sub_topic, subscriber, emitter}},
          id: emitter
        )
      end

    # Publish startup event instead of direct terminal output
    pool_name = name(store, sub_topic)
    emitter_count = length(emitter_names)
    
    LoggingPublisher.startup(
      :emitter_pool,
      store,
      "EMITTER POOL STARTUP",
      %{
        pool_name: pool_name,
        sub_topic: sub_topic,
        emitter_count: emitter_count
      }
    )
    
    # Broadcast emitter pool lifecycle event
    PubSubIntegration.broadcast_lifecycle_event(
      :emitter_pool_started,
      pool_name,
      %{
        store: store,
        sub_topic: sub_topic,
        emitter_count: emitter_count,
        subscriber: subscriber
      }
    )
    
    # Broadcast store-specific component health
    PubSubIntegration.broadcast_store_health(
      store,
      :emitter_pool,
      :healthy,
      %{
        sub_topic: sub_topic,
        emitter_count: emitter_count,
        event: :started
      }
    )

    Supervisor.init(children, strategy: :one_for_one)
  end

  def stop(store, sub_topic) do
    pool_name = name(store, sub_topic)
    
    # Publish shutdown event instead of direct terminal output
    LoggingPublisher.shutdown(
      :emitter_pool,
      store,
      "EMITTER POOL SHUTDOWN",
      %{
        pool_name: pool_name,
        sub_topic: sub_topic,
        reason: "Manual Stop"
      }
    )
    
    # Broadcast emitter pool shutdown lifecycle event
    PubSubIntegration.broadcast_lifecycle_event(
      :emitter_pool_stopped,
      pool_name,
      %{
        store: store,
        sub_topic: sub_topic,
        reason: "Manual Stop"
      }
    )
    
    # Broadcast store-specific component health update
    PubSubIntegration.broadcast_store_health(
      store,
      :emitter_pool,
      :unhealthy,
      %{
        sub_topic: sub_topic,
        event: :stopped,
        reason: "Manual Stop"
      }
    )
    
    Supervisor.stop(pool_name)
  end
end
