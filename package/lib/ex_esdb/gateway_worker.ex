defmodule ExESDB.GatewayWorker do
  @moduledoc """
    GatewayWorker processes are started on each node in the cluster,
    and contain the implementation functions for the Gater.API.
  """
  use GenServer

  alias ExESDB.SnapshotsReader, as: SnapshotsR
  alias ExESDB.SnapshotsWriter, as: SnapshotsW

  alias ExESDB.StoreRegistry, as: StoreRegistry

  alias ExESDB.SubscriptionsReader, as: SubsR
  alias ExESDB.SubscriptionsWriter, as: SubsW

  alias ExESDB.StreamsHelper, as: StreamsH
  alias ExESDB.StreamsReader, as: StreamsR
  alias ExESDB.StreamsWriter, as: StreamsW

  alias ExESDB.Themes, as: Themes

  alias ExESDB.ConsistencyChecker, as: ConsistencyChecker

  alias ExESDB.Events

  @type store :: atom()
  @type stream :: String.t()
  @type subscription_name :: String.t()
  @type error :: term
  @type subscription_type :: :by_stream | :by_event_type | :by_event_pattern
  @type selector_type :: String.t() | map()

  ############ HANDLE_CALL ############
  @impl GenServer
  def handle_call({:stream_forward, store, stream_id, start_version, count}, _from, state) do
    reply_with_stream_result(
      StreamsR.stream_events(store, stream_id, start_version, count, :forward),
      state
    )
  end

  @impl GenServer
  def handle_call({:stream_backward, store, stream_id, start_version, count}, _from, state) do
    reply_with_stream_result(
      StreamsR.stream_events(store, stream_id, start_version, count, :backward),
      state
    )
  end

  @impl GenServer
  def handle_call({:get_events, store, stream_id, start_version, count, direction}, _from, state) do
    result = StreamsR.stream_events(store, stream_id, start_version, count, direction)
    reply_with_enumerable_result(result, state)
  end

  @impl GenServer
  def handle_call({:get_streams, store}, _from, state) do
    case StreamsR.get_streams(store) do
      {:ok, streams} ->
        {:reply, {:ok, Enum.to_list(streams)}, state}
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
    # Publish stream write requested event
    topic = Events.build_topic(store, :gateway)
    event = Events.build_event(:stream_write_requested, %{stream_id: stream_id, expected_version: expected_version})
    Phoenix.PubSub.broadcast(ExESDB.PubSub, topic, {:gateway_event, event})

    current_version =
      store
      |> StreamsH.get_version!(stream_id)

    # Current version info published via events

    reply =
      case current_version
           |> version_matches?(expected_version) do
        true ->
          store
          |> StreamsW.append_events(stream_id, current_version, events)

        false ->
          {:error, {:wrong_expected_version, current_version}}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:read_snapshot, store, source_uuid, stream_uuid, version}, _from, state) do
    reply_with_result(
      SnapshotsR.read_snapshot(store, source_uuid, stream_uuid, version),
      state
    )
  end

  @impl GenServer
  def handle_call({:list_snapshots, store, source_uuid, stream_uuid}, _from, state) do
    reply_with_result(
      SnapshotsR.list_snapshots(store, source_uuid, stream_uuid),
      state
    )
  end

  @impl GenServer
  def handle_call({:verify_cluster_consistency, store}, _from, state) do
    reply_with_result(ConsistencyChecker.verify_cluster_consistency(store), state)
  end

  @impl GenServer
  def handle_call({:quick_health_check, store}, _from, state) do
    reply_with_result(ConsistencyChecker.quick_health_check(store), state)
  end

  @impl GenServer
  def handle_call({:verify_membership_consensus, store}, _from, state) do
    reply_with_result(ConsistencyChecker.verify_membership_consensus(store), state)
  end

  @impl GenServer
  def handle_call({:check_raft_log_consistency, store}, _from, state) do
    reply_with_result(ConsistencyChecker.check_raft_log_consistency(store), state)
  end

  @impl GenServer
  def handle_call({:list_stores}, _from, state) do
    {:ok, stores} = StoreRegistry.list_stores()
    {:reply, {:ok, stores}, state}
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

  ############# PLUMBING #############
  def child_spec(opts) do
    %{
      id: {__MODULE__, :rand.uniform(10_000)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts
    )
  end

  def gateway_worker_name(store_id),
    do: {:gateway_worker, store_id, node(), :rand.uniform(10_000)}

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    store_id = Keyword.get(opts, :store_id, :undefined_store_id)
    name = gateway_worker_name(store_id)
    new_state = Keyword.put(opts, :gateway_worker_name, name)
    
    # Publish gateway worker started event
    topic = Events.build_topic(store_id, :gateway)
    event = Events.build_event(:gateway_worker_started, %{worker_name: name})
    Phoenix.PubSub.broadcast(ExESDB.PubSub, topic, {:gateway_event, event})

    # Register with Swarm if available
    case register_with_swarm(name) do
      :ok ->
        {:ok, new_state}
      {:error, reason} ->
        # Publish registration failed event
        topic = Events.build_topic(store_id, :gateway)
        event = Events.build_event(:registration_failed, %{service: "swarm", reason: reason})
        Phoenix.PubSub.broadcast(ExESDB.PubSub, topic, {:gateway_event, event})
        {:ok, new_state}
    end
  end

  # Helper functions for safe Swarm operations
  defp register_with_swarm(name) do
    try do
      case Swarm.register_name(name, self()) do
        :yes -> :ok
        :no -> {:error, :already_registered}
        other -> {:error, other}
      end
    rescue
      error -> {:error, {:exception, error}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      type, reason -> {:error, {type, reason}}
    end
  end

  defp unregister_from_swarm(name) do
    try do
      Swarm.unregister_name(name)
      :ok
    rescue
      _error ->
        # Error during unregistration - silently handle
        :error
    catch
      :exit, _reason ->
        # Exit during unregistration - silently handle
        :error

      _type, _reason ->
        # Other error during unregistration - silently handle
        :error
    end
  end

  @impl true
  def terminate(reason, state) do
    name = Keyword.get(state, :gateway_worker_name)
    msg = "[#{inspect(name)}] is TERMINATED with reason #{inspect(reason)}, leaving the cluster."
    IO.puts("#{Themes.gateway_worker(self(), msg)}")
    unregister_from_swarm(name)
    :ok
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    name = Keyword.get(state, :gateway_worker_name)
    msg = "[#{inspect(name)}] is EXITING with reason #{inspect(reason)}, leaving the cluster."
    IO.puts("#{Themes.gateway_worker(self(), msg)}")
    unregister_from_swarm(name)
    {:noreply, state}
  end

  # Helper functions to reduce repetitive reply patterns
  defp reply_with_result({:ok, data}, state), do: {:reply, {:ok, data}, state}
  defp reply_with_result({:error, reason}, state), do: {:reply, {:error, reason}, state}

  defp reply_with_stream_result({:ok, stream}, state), do: {:reply, {:ok, stream}, state}
  defp reply_with_stream_result({:error, reason}, state), do: {:reply, {:error, reason}, state}

  defp reply_with_enumerable_result({:ok, data}, state) do
    {:reply, {:ok, Enum.to_list(data)}, state}
  end
  defp reply_with_enumerable_result({:error, reason}, state) do
    {:reply, {:error, reason}, state}
  end

  # Helper function to check if current version matches expected version
  defp version_matches?(_current, :any), do: true
  defp version_matches?(current, :stream_exists) when current >= 0, do: true
  # Stream doesn't exist
  defp version_matches?(-1, :stream_exists), do: false
  defp version_matches?(current, expected) when is_integer(expected), do: current == expected
end
