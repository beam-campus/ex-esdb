defmodule ExESDB.StreamsReaderWorker do
  @moduledoc """
    Provides functions for reading and streaming events from the event store_id.
  """
  use GenServer
  require Logger
  alias ExESDB.Themes, as: Themes

  alias ExESDB.StreamsHelper, as: Helper
  alias ExESDB.StreamsReader, as: StreamsReader

  import ExESDB.Khepri.Conditions

  defp try_register_with_swarm(name, store_id, stream_id, partition) do
    # Register with Swarm - handle potential registration failures
    case register_with_swarm(name) do
      :ok ->
        {:ok, build_initial_state(name, store_id, stream_id, partition)}

      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end

  defp fetch_single_event(store_id, stream_id, version) do
    # Use 0-based version directly as storage key
    padded_version = Helper.pad_version(version, 6)

    case :khepri.get(store_id, [:streams, stream_id, padded_version]) do
      {:ok, event} ->
        event

      {:error, :not_found} ->
        nil

      {:error, reason} ->
        Logger.warning(
          "Failed to read event #{version} from stream #{stream_id}: #{inspect(reason)}"
        )

        nil
    end
  end

  defp stream_events(store_id, stream_id, start_version, count, direction) do
    with :ok <- validate_parameters(start_version, count),
         {:ok, event_stream} <- fetch_events(store_id, stream_id, start_version, count, direction) do
      {:ok, event_stream}
    else
      # If stream doesn't exist, check if that's the real issue
      {:error, :stream_not_found} = error ->
        case validate_stream_exists(store_id, stream_id) do
          # Stream exists but fetch failed - propagate original error
          :ok ->
            error

          {:error, :stream_not_found} ->
            # Return empty stream for aggregate loading
            {:ok, []}
        end

      error ->
        error
    end
  end

  defp validate_stream_exists(store_id, stream_id) do
    exists = Helper.stream_exists?(store_id, stream_id)

    if exists do
      :ok
    else
      {:error, :stream_not_found}
    end
  end

  defp validate_parameters(start_version, count) do
    cond do
      not is_integer(start_version) -> {:error, {:invalid_start_version, start_version}}
      start_version < 0 -> {:error, :invalid_start_version}
      not is_integer(count) -> {:error, {:invalid_count, count}}
      count < 1 -> {:error, :invalid_count}
      true -> :ok
    end
  end

  defp fetch_events(store_id, stream_id, start_version, count, direction) do
    stream_length = Helper.get_version!(store_id, stream_id)

    # Validate stream_length is a proper integer
    case stream_length do
      length when is_integer(length) and length >= -1 ->
        desired_versions = Helper.calculate_versions(start_version, count, direction)

        valid_versions =
          Enum.filter(desired_versions, fn version ->
            version >= 0 && version <= length
          end)

        event_stream =
          valid_versions
          |> Stream.map(&fetch_single_event(store_id, stream_id, &1))
          |> Stream.reject(&is_nil/1)

        {:ok, event_stream}

      invalid_length ->
        Logger.warning(
          "Invalid stream length #{inspect(invalid_length)} for stream #{stream_id}, treating as empty stream"
        )

        # Return empty stream instead of error to avoid breaking aggregate loading
        {:ok, []}
    end
  end

  ############ CALLBACKS ############
  @impl true
  def handle_call(
        {:stream_events, store_id, stream_id, start_version, count, direction},
        _from,
        state
      ) do
    result = stream_events(store_id, stream_id, start_version, count, direction)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_streams, store_id}, _from, state) do
    result = get_streams_safe(store_id)
    {:reply, result, state}
  end

  # Handle unexpected call messages gracefully
  @impl true
  def handle_call(unknown_call, _from, state) do
    Logger.warning("Unknown call received: #{inspect(unknown_call)}")
    {:reply, {:error, :unknown_call}, state}
  end

  defp get_streams_safe(store_id) do
    case :khepri.get_many(store_id, [
           :streams,
           if_node_exists(exists: true)
         ]) do
      {:ok, stream_data} ->
        streams =
          Enum.reduce(stream_data, [], fn
            {[:streams, stream_id], _stream}, acc
            when is_binary(stream_id) or is_atom(stream_id) ->
              [stream_id | acc]

            {invalid_key, _}, acc ->
              Logger.warning("Invalid stream key format: #{inspect(invalid_key)}")
              acc
          end)

        {:ok, Enum.reverse(streams)}

      {:error, reason} ->
        Logger.error("Failed to get streams: #{inspect(reason)}")
        {:error, :store_id_access_failed}
    end
  end

  ################## PlUMBING ##################

  @impl true
  def init({store_id, stream_id, partition}) do
    Process.flag(:trap_exit, true)
    name = StreamsReader.worker_id(store_id, stream_id)

    # Validate initialization parameters
    case validate_init_params(store_id, stream_id, partition) do
      :ok ->
        # Safe logging - avoid potential crashes from theme formatting
        safe_log_startup(name, partition)

        try_register_with_swarm(name, store_id, stream_id, partition)

      {:error, reason} ->
        Logger.error("Invalid initialization parameters: #{inspect(reason)}")
        {:stop, {:invalid_params, reason}}
    end
  end

  defp validate_init_params(store_id, stream_id, partition) do
    cond do
      is_nil(store_id) -> {:error, :store_required}
      is_nil(stream_id) or stream_id == "" -> {:error, :stream_id_required}
      is_nil(partition) -> {:error, :partition_required}
      not is_integer(partition) -> {:error, :partition_must_be_integer}
      true -> :ok
    end
  end

  defp safe_log_startup(name, partition) do
    # Use pattern matching to handle theme formatting safely
    case Themes.streams_reader_worker(self(), "[#{inspect(name)}] is UP on partition #{inspect(partition)}, joining the cluster.") do
      themed_msg when is_binary(themed_msg) ->
        IO.puts(themed_msg)
      
      _other ->
        # Fallback to basic logging if theme formatting fails
        Logger.info(
          "StreamsReaderWorker #{inspect(name)} starting on partition #{inspect(partition)}"
        )
    end
  end

  defp register_with_swarm(name) do
    case Swarm.register_name(name, self()) do
      :yes -> :ok
      :no -> {:error, :name_already_registered}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  defp build_initial_state(name, store_id, stream_id, partition) do
    %{
      worker_name: name,
      store_id: store_id,
      stream_id: stream_id,
      node: node(),
      partition: partition,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  def child_spec({store_id, stream_id, partition} = args) do
    # Validate parameters early to fail fast
    case validate_child_spec_params(store_id, stream_id, partition) do
      :ok ->
        %{
          id: {StreamsReader.worker_id(store_id, stream_id), partition},
          start: {__MODULE__, :start_link, [args]},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }

      {:error, reason} ->
        raise ArgumentError, "Invalid child_spec parameters: #{inspect(reason)}"
    end
  end

  defp validate_child_spec_params(store_id, stream_id, partition) do
    cond do
      is_nil(store_id) -> {:error, :store_required}
      is_nil(stream_id) or stream_id == "" -> {:error, :stream_id_required}
      is_nil(partition) -> {:error, :partition_required}
      not is_integer(partition) -> {:error, :partition_must_be_integer}
      true -> :ok
    end
  end

  def start_link({store_id, stream_id, partition} = args) do
    # Validate parameters before attempting to start
    case validate_child_spec_params(store_id, stream_id, partition) do
      :ok ->
        worker_id = StreamsReader.worker_id(store_id, stream_id)

        GenServer.start_link(
          __MODULE__,
          args,
          name: {:global, worker_id}
        )

      {:error, reason} ->
        {:error, {:invalid_params, reason}}
    end
  end

  # Handle unexpected info messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Handle unexpected cast messages
  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Unexpected cast message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Graceful termination
  @impl true
  def terminate(reason, _state) do
    # Only log unexpected termination reasons
    case reason do
      :normal -> :ok
      :shutdown -> :ok
      {:shutdown, _} -> :ok
      _ -> Logger.warning("StreamsReaderWorker terminating unexpectedly: #{inspect(reason)}")
    end

    :ok
  end
end
