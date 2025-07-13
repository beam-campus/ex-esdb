defmodule ExESDB.LeaderTracker do
  @moduledoc """
    As part of the ExESDB.System, the SubscriptionsTracker is responsible for
    observing the subscriptions that are maintained in the Store.

    Since Khepri triggers are executed on the leader node, the SubscriptionsTracker
    will be instructed to start the Emitters system on the leader node whenever a new subscription
    is registered.

    When a Subscription is deleted, the SubscriptionsTracker will instruct the Emitters system to stop 
    the associated EmitterPool.
  """
  use GenServer

  require Logger

  alias ExESDB.Emitters, as: Emitters
  alias ExESDB.KhepriCluster, as: KhepriCluster

  ########### PRIVATE HELPERS ###########

  @doc """
  Formats subscription data from Khepri into the format expected by Emitters.
  """
  defp format_subscription_data(data) do
    # Handle different possible data formats from Khepri
    case data do
      # If data is already in the expected format
      %{
        type: _type,
        subscription_name: _subscription_name,
        selector: _selector,
        subscriber: _subscriber
      } = formatted_data ->
        formatted_data

      # If data has different key names, map them
      %{} = map_data ->
        %{
          type: Map.get(map_data, :type) || Map.get(map_data, "type"),
          subscription_name:
            Map.get(map_data, :subscription_name) || Map.get(map_data, "subscription_name") ||
              Map.get(map_data, :name),
          selector: Map.get(map_data, :selector) || Map.get(map_data, "selector"),
          subscriber:
            Map.get(map_data, :subscriber) || Map.get(map_data, "subscriber") ||
              Map.get(map_data, :subscriber_pid)
        }

      # Fallback: log the data format and return a default structure
      _ ->
        Logger.warning("Unknown subscription data format", data: data)

        %{
          type: :by_stream,
          subscription_name: "unknown",
          selector: "unknown",
          subscriber: nil
        }
    end
  end

  ########### HANDLE_INFO ###########
  @impl GenServer
  def handle_info({:feature_created, :subscriptions, data}, state) do
    Logger.info("Subscription registered", subscription: data)
    store = state[:store_id]

    if KhepriCluster.leader?(store) do
      # Extract subscription data and start emitter pool
      subscription_data = format_subscription_data(data)

      case Emitters.start_emitter_pool(store, subscription_data) do
        {:ok, _pid} ->
          Logger.info("EmitterPool started", subscription: subscription_data.subscription_name)

        {:error, {:already_started, _pid}} ->
          Logger.debug("EmitterPool already exists", subscription: subscription_data.subscription_name)

        {:error, reason} ->
          Logger.error("Failed to start EmitterPool", subscription: subscription_data.subscription_name, reason: reason)
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:feature_updated, :subscriptions, data}, state) do
    Logger.info("Subscription updated", subscription: data)

    if KhepriCluster.leader?(state[:store_id]) do
      subscription_data = format_subscription_data(data)

      try do
        Emitters.update_emitter_pool(state[:store_id], subscription_data)

        Logger.debug("EmitterPool updated", subscription: subscription_data.subscription_name)
      rescue
        error ->
          Logger.error("Failed to update EmitterPool", subscription: subscription_data.subscription_name, error: error)
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:feature_deleted, :subscriptions, data}, state) do
    Logger.info("Subscription deleted", subscription: data)

    if KhepriCluster.leader?(state[:store_id]) do
      subscription_data = format_subscription_data(data)

      try do
        Emitters.stop_emitter_pool(state[:store_id], subscription_data)

        Logger.debug("EmitterPool stopped", subscription: subscription_data.subscription_name)
      rescue
        error ->
          Logger.error("Failed to stop EmitterPool", subscription: subscription_data.subscription_name, error: error)
      end
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.debug("LeaderTracker process exited", pid: pid, reason: reason)
    store = state[:store_id]

    store
    |> :tracker_group.leave(:subscriptions, self())

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_, state) do
    {:noreply, state}
  end

  ############## PLUMBING ##############
  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    store = Keyword.get(opts, :store_id)
    Logger.info("LeaderTracker started", pid: self())

    :ok =
      store
      |> :subscriptions.setup_tracking(self())

    {:ok, opts}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("LeaderTracker terminating", reason: reason)
    store = state[:store_id]

    store
    |> :tracker_group.leave(:subscriptions, self())

    :ok
  end

  def child_spec(opts),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }

  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )
end
