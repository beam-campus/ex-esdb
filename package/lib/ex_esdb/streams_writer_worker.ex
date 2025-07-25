defmodule ExESDB.StreamsWriterWorker do
  @moduledoc """
    Provides functions for writing streams
  """

  use GenServer

  alias ExESDB.Options, as: Options
  alias ExESDB.StreamsHelper, as: Helper
  alias ExESDB.StreamsWriter, as: StreamsWriter
  alias ExESDB.Themes, as: Themes

  require Logger
  require DateTime

  ############ INTERNALS ############
  defp handle_transaction_result({:ok, {:commit, result}}), do: {:ok, result}
  defp handle_transaction_result({:ok, {:abort, reason}}), do: {:error, reason}
  defp handle_transaction_result({:error, reason}), do: {:error, reason}

  defp epoch_time_ms,
    do: DateTime.to_unix(DateTime.utc_now(), :millisecond)

  defp check_idle(ttl) do
    Process.send_after(self(), :check_idle, ttl)
  end

  defp append_with_write(store, stream_id, padded_version, recorded_event) do
    res =
      store
      |> :khepri.put!([:streams, stream_id, padded_version], recorded_event)

    # Request asynchronous persistence via PersistenceWorker
    #   spawn(fn -> PersistenceWorker.request_persistence(store) end)
    res
  end

  defp try_append_events(store, stream_id, expected_version, events) do
    current_version = Helper.get_version!(store, stream_id)

    if current_version == expected_version do
      final_version = append_events_to_stream(events, current_version, stream_id, store)
      {:ok, final_version}
    else
      {:error, :wrong_expected_version}
    end
  end

  defp append_events_to_stream(events, current_version, stream_id, store) do
    events
    |> Enum.with_index()
    |> Enum.reduce(current_version, fn {event, index}, _acc ->
      # Calculate next version: for new streams (current_version = -1),
      # first event gets version 0. For existing streams, increment from current.
      new_version = current_version + 1 + index
      recorded_event = create_recorded_event(event, stream_id, new_version)
      append_recorded_event(store, stream_id, new_version, recorded_event)
      new_version
    end)
  end

  defp create_recorded_event(event, stream_id, new_version) do
    now = DateTime.utc_now()
    Helper.to_event_record(event, stream_id, new_version, now, DateTime.to_unix(now, :microsecond))
  end

  defp append_recorded_event(store, stream_id, new_version, recorded_event) do
    padded_version = Helper.pad_version(new_version, 6)
    append_with_write(store, stream_id, padded_version, recorded_event)
  end

  ############ CALLBACKS ############
  @impl true
  def handle_call({:append_events_tx, store, stream_id, expected_version, events}, _from, state) do
    result =
      case store
           |> :khepri.transaction(fn ->
             store
             |> try_append_events(stream_id, expected_version, events)
           end)
           |> handle_transaction_result() do
        {:ok, new_version} ->
          {:ok, new_version}

        {:error, reason} ->
          {:error, reason}
      end

    state = %{state | idle_since: epoch_time_ms()}
    {:reply, result, state}
  end

  @impl true
  def handle_call({:append_events, store, stream_id, expected_version, events}, _from, state) do
    result =
      store
      |> try_append_events(stream_id, expected_version, events)

    state = %{state | idle_since: epoch_time_ms()}
    {:reply, result, state}
  end

  @impl true
  def handle_info(:check_idle, %{idle_since: idle_since} = state) do
    writer_ttl = Options.writer_idle_ms()

    if idle_since + writer_ttl < epoch_time_ms() do
      Process.exit(self(), :ttl_reached)
      # GenServer.stop(self())
    end

    check_idle(writer_ttl)
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, %{worker_name: name} = state) do
    Swarm.unregister_name(name)
    {:noreply, state}
  end

  ############# PLUMBING #############
  @doc """
    Returns a child spec for a streams writer worker.
    Please note that the restart strategy is set to `:temporary`
    to avoid restarting the worker when the idle timeout is reached.
  """
  def child_spec({store, stream_id, partition}) do
    %{
      id: StreamsWriter.hr_worker_id_atom(store, stream_id),
      start: {__MODULE__, :start_link, [{store, stream_id, partition}]},
      type: :worker,
      restart: :temporary,
      shutdown: 5000
    }
  end

  def start_link({store, stream_id, partition}) do
    GenServer.start_link(
      __MODULE__,
      {store, stream_id, partition},
      name: StreamsWriter.hr_worker_id_atom(store, stream_id)
    )
  end

  @impl true
  def init({store, stream_id, partition}) do
    Process.flag(:trap_exit, true)
    ttl = Options.writer_idle_ms()
    name = StreamsWriter.hr_worker_id_atom(store, stream_id)
    msg = "[#{inspect(name)}] is UP on partition #{inspect(partition)}, joining the cluster."
    IO.puts("#{Themes.streams_writer_worker(self(), msg)}")
    Swarm.register_name(name, self())
    check_idle(ttl)

    {:ok,
     %{
       worker_name: name,
       store: store,
       stream_id: stream_id,
       partition: partition,
       node: node(),
       idle_since: epoch_time_ms()
     }}
  end

  @impl true
  def terminate(_reason, %{worker_name: name}) do
    Swarm.unregister_name(name)
    :ok
  end
end
