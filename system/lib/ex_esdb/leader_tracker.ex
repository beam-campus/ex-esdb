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

  alias ExESDB.Emitters, as: Emitters
  alias ExESDB.StoreCluster, as: StoreCluster
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  ########### PRIVATE HELPERS ###########

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
        IO.puts("Warning: Unknown subscription data format: #{inspect(data)}")

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
    IO.puts("Subscription #{inspect(data)} registered")
    store = state[:store_id]

    if StoreCluster.leader?(store) do
      # Make sure the LeaderWorker is running
      case Process.whereis(ExESDB.LeaderWorker) do
        nil ->
          IO.puts("LeaderWorker is not running. Starting LeaderWorker...")
          case ExESDB.LeaderWorker.start_link(store_id: store) do
            {:ok, _pid} ->
              IO.puts("LeaderWorker started successfully.")
              :ok
            {:error, reason} ->
              IO.puts("Failed to start LeaderWorker: #{inspect(reason)}")
              {:error, reason}
          end
        _pid ->
          :ok
      end

      # Extract subscription data and start emitter pool
      subscription_data = format_subscription_data(data)

      case Emitters.start_emitter_pool(store, subscription_data) do
        {:ok, _pid} ->
          IO.puts(
            "Successfully started EmitterPool for subscription #{subscription_data.subscription_name}"
          )

        {:error, {:already_started, _pid}} ->
          IO.puts(
            "EmitterPool already exists for subscription #{subscription_data.subscription_name}"
          )

        {:error, reason} ->
          IO.puts(
            "Failed to start EmitterPool for subscription #{subscription_data.subscription_name}: #{inspect(reason)}"
          )
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:feature_updated, :subscriptions, data}, state) do
    IO.puts("Subscription #{inspect(data)} updated")

    if StoreCluster.leader?(state[:store_id]) do
      subscription_data = format_subscription_data(data)

      try do
        Emitters.update_emitter_pool(state[:store_id], subscription_data)

        IO.puts(
          "Successfully updated EmitterPool for subscription #{subscription_data.subscription_name}"
        )
      rescue
        error ->
          IO.puts(
            "Failed to update EmitterPool for subscription #{subscription_data.subscription_name}: #{inspect(error)}"
          )
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:feature_deleted, :subscriptions, data}, state) do
    IO.puts("Subscription #{inspect(data)} deleted")

    if StoreCluster.leader?(state[:store_id]) do
      subscription_data = format_subscription_data(data)

      try do
        Emitters.stop_emitter_pool(state[:store_id], subscription_data)

        IO.puts(
          "Successfully stopped EmitterPool for subscription #{subscription_data.subscription_name}"
        )
      rescue
        error ->
          IO.puts(
            "Failed to stop EmitterPool for subscription #{subscription_data.subscription_name}: #{inspect(error)}"
          )
      end
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    IO.puts("#{Themes.leader_tracker(pid, "exited with reason: #{inspect(reason)}")}")
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
    IO.puts("#{Themes.leader_tracker(self(), "is UP.")}")

    :ok =
      store
      |> :subscriptions.setup_tracking(self())

    {:ok, opts}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("#{Themes.leader_tracker(self(), "terminating with reason: #{inspect(reason)}")}")
    store = state[:store_id]

    store
    |> :tracker_group.leave(:subscriptions, self())

    :ok
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

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end
end
