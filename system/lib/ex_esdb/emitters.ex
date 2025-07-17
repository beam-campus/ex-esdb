defmodule ExESDB.Emitters do
  @moduledoc """
    As part of the ExESDB.System, ExESDB.Emitters is responsible for managing the
    lifetime of the Emitter processes.
  """
  alias ExESDB.Topics, as: Topics

  defp build_filter(:by_stream, selector), do: :streams_filters.by_stream(selector)
  defp build_filter(:by_event_type, selector), do: :streams_filters.by_event_type(selector)
  defp build_filter(:by_event_pattern, selector), do: :streams_filters.by_event_pattern(selector)
  defp build_filter(:by_event_payload, selector), do: :streams_filters.by_event_payload(selector)

  defp partition(term) do
    partitions = System.schedulers_online()
    :erlang.phash2(term, :rand.uniform(partitions))
  end

  def start_emitter_pool(
        store,
        %{
          type: type,
          subscription_name: subscription_name,
          selector: selector,
          subscriber: subscriber
        },
        pool_size \\ 1
      ) do
    filter =
      type
      |> build_filter(selector)

    sub_topic = Topics.sub_topic(type, subscription_name, selector)

    args = {store, sub_topic, subscriber, pool_size, filter}

    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.EmitterPools, store)
    
    DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {partition_name, partition(args)}},
      {ExESDB.EmitterPool, args}
    )
  end

  @doc """
  Stops an EmitterPool for a given subscription.
  """
  def stop_emitter_pool(
        store,
        %{
          type: type,
          subscription_name: subscription_name,
          selector: selector
        }
      ) do
    sub_topic = Topics.sub_topic(type, subscription_name, selector)
    ExESDB.EmitterPool.stop(store, sub_topic)
  end

  @doc """
  Updates an EmitterPool with new subscription data.
  This is typically called when the subscriber PID changes.
  """
  def update_emitter_pool(
        store,
        %{
          type: type,
          subscription_name: subscription_name,
          selector: selector,
          subscriber: new_subscriber
        } = subscription_data
      ) do
    sub_topic = Topics.sub_topic(type, subscription_name, selector)
    pool_name = ExESDB.EmitterPool.name(store, sub_topic)
    
    # Check if the pool exists
    case Process.whereis(pool_name) do
      nil ->
        # Pool doesn't exist, start it
        start_emitter_pool(store, subscription_data)
        
      pool_pid ->
        # Pool exists, update the workers with new subscriber PID
        update_pool_workers(pool_pid, new_subscriber)
    end
  end
  
  defp update_pool_workers(pool_pid, new_subscriber) do
    # Get all child workers from the supervisor
    children = Supervisor.which_children(pool_pid)
    
    # Send update message to each worker
    Enum.each(children, fn {_id, worker_pid, :worker, _modules} ->
      if worker_pid != :undefined and Process.alive?(worker_pid) do
        GenServer.cast(worker_pid, {:update_subscriber, new_subscriber})
      end
    end)
  end
end
