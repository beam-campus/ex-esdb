defmodule ExESDB.GatewayWorker do
  @moduledoc """
    GatewayWorker processes are started on each node in the cluster,
    and contain the implementation functions for the Gater.API.
  """
  use GenServer

  alias ExESDB.SnapshotsReader, as: SnapshotsR
  alias ExESDB.SnapshotsWriter, as: SnapshotsW

  alias ExESDB.SubscriptionsReader, as: SubsR
  alias ExESDB.SubscriptionsWriter, as: SubsW

  alias ExESDB.StreamsHelper, as: StreamsH
  alias ExESDB.StreamsReader, as: StreamsR
  alias ExESDB.StreamsWriter, as: StreamsW

  require Logger

  @type store :: atom()
  @type stream :: String.t()
  @type subscription_name :: String.t()
  @type error :: term
  @type subscription_type :: :by_stream | :by_event_type | :by_event_pattern
  @type selector_type :: String.t() | map()

  ############ HANDLE_CALL ############
  @impl GenServer
  def handle_call({:stream_forward, store, stream_id, start_version, count}, _from, state) do
    case store
         |> StreamsR.stream_events(stream_id, start_version, count, :forward) do
      {:ok, event_stream} ->
        {:reply, {:ok, event_stream}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:stream_backward, store, stream_id, start_version, count}, _from, state) do
    case store
         |> StreamsR.stream_events(stream_id, start_version, count, :backward) do
      {:ok, event_stream} ->
        {:reply, {:ok, event_stream}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_events, store, stream_id, start_version, count, direction}, _from, state) do
    case store
         |> StreamsR.stream_events(stream_id, start_version, count, direction) do
      {:ok, events} ->
        {:reply, {:ok, events |> Enum.to_list()}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_streams, store}, _from, state) do
    case store
         |> StreamsR.get_streams() do
      {:ok, streams} ->
        {:reply, {:ok, streams |> Enum.to_list()}, state}

      {:error, _reason} ->
        {:reply, {:ok, []}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_subscriptions, store}, _from, state) do
    reply =
      store
      |> SubsR.get_subscriptions()

    {:reply, {:ok, reply}, state}
  end

  @impl GenServer
  def handle_call({:get_version, store, stream}, _from, state) do
    version =
      store
      |> StreamsH.get_version!(stream)

    {:reply, {:ok, version}, state}
  end

  @impl GenServer
  def handle_call({:append_events, store, stream_id, events}, _from, state) do
    current_version =
      store
      |> StreamsH.get_version!(stream_id)

    reply =
      store
      |> StreamsW.append_events(stream_id, current_version, events)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:append_events, store, stream_id, expected_version, events}, _from, state) do
    current_version =
      store
      |> StreamsH.get_version!(stream_id)

    Logger.info(
      "GATEWAY: stream_id=#{stream_id}, current_version=#{inspect(current_version)}, expected_version=#{inspect(expected_version)}"
    )

    matches = version_matches?(current_version, expected_version)

    Logger.info(
      "GATEWAY: version_matches?(#{inspect(current_version)}, #{inspect(expected_version)}) = #{matches}"
    )

    reply =
      case matches do
        true ->
          Logger.info("GATEWAY: Proceeding with event append for stream #{stream_id}")

          store
          |> StreamsW.append_events(stream_id, current_version, events)

        false ->
          Logger.error(
            "GATEWAY: Version mismatch for stream #{stream_id}: current=#{current_version}, expected=#{expected_version}"
          )

          {:error, {:wrong_expected_version, current_version}}
      end

    {:reply, reply, state}
  end

  # Helper function to check if current version matches expected version
  defp version_matches?(_current, :any), do: true
  defp version_matches?(current, :stream_exists) when current >= 0, do: true
  # Stream doesn't exist
  defp version_matches?(-1, :stream_exists), do: false
  defp version_matches?(current, expected) when is_integer(expected), do: current == expected

  @impl GenServer
  def handle_call({:read_snapshot, store, source_uuid, stream_uuid, version}, _from, state) do
    case store
         |> SnapshotsR.read_snapshot(source_uuid, stream_uuid, version) do
      {:ok, snapshot} ->
        {:reply, {:ok, snapshot}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_snapshots, store, source_uuid, stream_uuid}, _from, state) do
    case store
         |> SnapshotsR.list_snapshots(source_uuid, stream_uuid) do
      {:ok, snapshots} ->
        {:reply, {:ok, snapshots}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_stores, _from, state) do
    stores = ExESDB.StoreManager.list_stores()
    {:reply, {:ok, stores}, state}
  end

  @impl GenServer
  def handle_call({:get_store_status, store_id}, _from, state) do
    case ExESDB.StoreManager.get_store_status(store_id) do
      {:ok, status} ->
        {:reply, {:ok, status}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_store_config, store_id}, _from, state) do
    case ExESDB.StoreManager.get_store_config(store_id) do
      {:ok, config} ->
        {:reply, {:ok, config}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  ################ HANDLE_CAST #############
  @impl true
  def handle_cast(
        {:remove_subscription, store, type, selector, subscription_name},
        state
      ) do
    store
    |> SubsW.delete_subscription(type, selector, subscription_name)

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:save_subscription, store, type, selector, subscription_name, start_from, subscriber},
        state
      ) do
    store
    |> SubsW.put_subscription(type, selector, subscription_name, start_from, subscriber)

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:ack_event, store, subscription_name, subscriber_pid, event},
        state
      ) do
    %{
      event_stream_id: stream_id,
      event_number: event_number
    } = event

    # Use 0-based versioning: next event to process is event_number + 1
    store
    |> SubsW.put_subscription(
      :by_stream,
      "$#{stream_id}",
      subscription_name,
      event_number + 1,
      subscriber_pid
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:record_snapshot, store, source_uuid, stream_uuid, version, snapshot_record},
        state
      ) do
    store
    |> SnapshotsW.record_snapshot(source_uuid, stream_uuid, version, snapshot_record)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:delete_snapshot, store, source_uuid, stream_uuid, version}, state) do
    store
    |> SnapshotsW.delete_snapshot(source_uuid, stream_uuid, version)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:create_store, store_id, config}, state) do
    case ExESDB.StoreManager.create_store(store_id, config) do
      {:ok, ^store_id} ->
        Logger.info("Successfully created store: #{store_id}")

      {:error, reason} ->
        Logger.error("Failed to create store #{store_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_store, store_id}, state) do
    case ExESDB.StoreManager.remove_store(store_id) do
      :ok ->
        Logger.info("Successfully removed store: #{store_id}")

      {:error, reason} ->
        Logger.error("Failed to remove store #{store_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  ############# PLUMBING #############
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: __MODULE__
    )
  end

  def gateway_worker_name,
    do: {:gateway_worker, node(), :rand.uniform(10_000)}

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    name = gateway_worker_name()
    new_state = Keyword.put(opts, :gateway_worker_name, name)
    Logger.info("GatewayWorker started, joining cluster", name: name)
    Swarm.register_name(name, self())
    {:ok, new_state}
  end

  @impl true
  def terminate(reason, state) do
    name = Keyword.get(state, :gateway_worker_name)
    Logger.info("GatewayWorker terminated, leaving cluster", name: name, reason: reason)
    Swarm.unregister_name(name)
    :ok
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    name = Keyword.get(state, :gateway_worker_name)
    Logger.warning("GatewayWorker exiting unexpectedly", name: name, reason: reason)
    Swarm.unregister_name(name)
    {:noreply, state}
  end
end
