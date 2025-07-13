defmodule ExESDB.StreamsReaderWorker do
  @moduledoc """
    Provides functions for reading and streaming events from the event store.
  """
  use GenServer
  require Logger

  alias ExESDB.StreamsHelper, as: Helper
  alias ExESDB.StreamsReader, as: StreamsReader

  import ExESDB.Khepri.Conditions

  ############ CALLBACKS ############
  @impl true
  def handle_call(
        {:stream_events, store, stream_id, start_version, count, direction},
        _from,
        state
      ) do
    result = stream_events(store, stream_id, start_version, count, direction)
    {:reply, result, state}
  end

  defp stream_events(store, stream_id, start_version, count, direction) do
    with :ok <- validate_parameters(start_version, count),
         {:ok, event_stream} <- fetch_events(store, stream_id, start_version, count, direction) do
      {:ok, event_stream}
    else
      # If stream doesn't exist, check if that's the real issue
      {:error, :stream_not_found} = error ->
        case validate_stream_exists(store, stream_id) do
          :ok -> error  # Stream exists but fetch failed - propagate original error
          {:error, :stream_not_found} -> 
            Logger.info("Stream #{stream_id} not found, returning empty stream for aggregate loading")
            {:ok, []}  # Return empty stream for aggregate loading
        end
      
      error -> error
    end
  rescue
    error ->
      Logger.error("Error reading stream #{stream_id}: #{inspect(error)}")
      {:error, :internal_error}
  end

  defp validate_stream_exists(store, stream_id) do
    exists = Helper.stream_exists?(store, stream_id)
    
    if exists do
      Logger.debug("Stream validation: #{stream_id} exists")
      :ok
    else
      Logger.warning("Stream validation: #{stream_id} not found in store #{store}")
      
      # Try to list available streams for debugging
      case get_streams_safe(store) do
        {:ok, streams} when is_list(streams) and length(streams) > 0 ->
          sample_streams = Enum.take(streams, 5)
          Logger.warning("Available streams (sample): #{inspect(sample_streams)}")
        
        {:ok, []} ->
          Logger.warning("No streams found in store #{store}")
        
        {:error, reason} ->
          Logger.warning("Could not list streams: #{inspect(reason)}")
      end
      
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

  defp fetch_events(store, stream_id, start_version, count, direction) do
    stream_length = Helper.get_version!(store, stream_id)
    
    # Validate stream_length is a proper integer
    case stream_length do
      length when is_integer(length) and length >= -1 ->
        desired_versions = Helper.calculate_versions(start_version, count, direction)
        
        valid_versions = Enum.filter(desired_versions, fn version ->
          version >= 0 && version <= length
        end)
        
        event_stream =
          valid_versions
          |> Stream.map(&fetch_single_event(store, stream_id, &1))
          |> Stream.reject(&is_nil/1)
        
        {:ok, event_stream}
        
      invalid_length ->
        Logger.warning("Invalid stream length #{inspect(invalid_length)} for stream #{stream_id}, treating as empty stream")
        # Return empty stream instead of error to avoid breaking aggregate loading
        {:ok, []}
    end
  end

  defp fetch_single_event(store, stream_id, version) do
    # Use 0-based version directly as storage key
    padded_version = Helper.pad_version(version, 6)
    
    case :khepri.get(store, [:streams, stream_id, padded_version]) do
      {:ok, event} -> event
      {:error, :not_found} -> nil
      {:error, reason} -> 
        Logger.warning("Failed to read event #{version} from stream #{stream_id}: #{inspect(reason)}")
        nil
    end
  end

  @impl true
  def handle_call({:get_streams, store}, _from, state) do
    result = get_streams_safe(store)
    {:reply, result, state}
  end

  # Handle unexpected call messages gracefully
  @impl true
  def handle_call(unknown_call, _from, state) do
    Logger.warning("Unknown call received: #{inspect(unknown_call)}")
    {:reply, {:error, :unknown_call}, state}
  end

  defp get_streams_safe(store) do
    try do
      case :khepri.get_many(store, [
        :streams,
        if_node_exists(exists: true)
      ]) do
        {:ok, stream_data} ->
          streams = Enum.reduce(stream_data, [], fn
            {[:streams, stream_id], _stream}, acc when is_binary(stream_id) or is_atom(stream_id) ->
              [stream_id | acc]
            {invalid_key, _}, acc ->
              Logger.warning("Invalid stream key format: #{inspect(invalid_key)}")
              acc
          end)
          {:ok, Enum.reverse(streams)}
        
        {:error, reason} ->
          Logger.error("Failed to get streams: #{inspect(reason)}")
          {:error, :store_access_failed}
      end
    rescue
      error ->
        Logger.error("Error getting streams: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  ################## PlUMBING ##################

  @impl true
  def init({store, stream_id, partition}) do
    try do
      # Validate initialization parameters
      with :ok <- validate_init_params(store, stream_id, partition) do
        Process.flag(:trap_exit, true)
        name = StreamsReader.worker_id(store, stream_id)
        
        # Safe logging - avoid potential crashes from theme formatting
        safe_log_startup(name, partition)
        
        # Register with Swarm - handle potential registration failures
        case register_with_swarm(name) do
          :ok ->
            {:ok, build_initial_state(name, store, stream_id, partition)}
          {:error, reason} ->
            Logger.error("Failed to register worker #{inspect(name)}: #{inspect(reason)}")
            {:stop, {:registration_failed, reason}}
        end
      else
        {:error, reason} ->
          Logger.error("Invalid initialization parameters: #{inspect(reason)}")
          {:stop, {:invalid_params, reason}}
      end
    rescue
      error ->
        Logger.error("Error during worker initialization: #{inspect(error)}")
        {:stop, {:init_error, error}}
    end
  end

  defp validate_init_params(store, stream_id, partition) do
    cond do
      is_nil(store) -> {:error, :store_required}
      is_nil(stream_id) or stream_id == "" -> {:error, :stream_id_required}
      is_nil(partition) -> {:error, :partition_required}
      not is_integer(partition) -> {:error, :partition_must_be_integer}
      true -> :ok
    end
  end

  defp safe_log_startup(name, partition) do
    Logger.info("StreamsReaderWorker [#{inspect(name)}] is UP on partition #{inspect(partition)}, joining the cluster.")
  end

  defp register_with_swarm(name) do
    try do
      case Swarm.register_name(name, self()) do
        :yes -> :ok
        :no -> {:error, :name_already_registered}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_response, other}}
      end
    rescue
      error -> {:error, {:swarm_error, error}}
    end
  end

  defp build_initial_state(name, store, stream_id, partition) do
    %{
      worker_name: name,
      store: store,
      stream_id: stream_id,
      node: node(),
      partition: partition,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  def child_spec({store, stream_id, partition} = args) do
    # Validate parameters early to fail fast
    case validate_child_spec_params(store, stream_id, partition) do
      :ok ->
        %{
          id: {StreamsReader.worker_id(store, stream_id), partition},
          start: {__MODULE__, :start_link, [args]},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }
      {:error, reason} ->
        raise ArgumentError, "Invalid child_spec parameters: #{inspect(reason)}"
    end
  end

  defp validate_child_spec_params(store, stream_id, partition) do
    cond do
      is_nil(store) -> {:error, :store_required}
      is_nil(stream_id) or stream_id == "" -> {:error, :stream_id_required}
      is_nil(partition) -> {:error, :partition_required}
      not is_integer(partition) -> {:error, :partition_must_be_integer}
      true -> :ok
    end
  end

  def start_link({store, stream_id, partition} = args) do
    # Validate parameters before attempting to start
    case validate_child_spec_params(store, stream_id, partition) do
      :ok ->
        worker_id = StreamsReader.worker_id(store, stream_id)
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
  def handle_info(msg, state) do
    Logger.debug("Unexpected info message: #{inspect(msg)}")
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
  def terminate(reason, state) do
    worker_name = Map.get(state, :worker_name, "unknown")
    
    case reason do
      :normal ->
        Logger.info("StreamsReaderWorker #{inspect(worker_name)} terminating normally")
      :shutdown ->
        Logger.info("StreamsReaderWorker #{inspect(worker_name)} shutting down")
      {:shutdown, _} ->
        Logger.info("StreamsReaderWorker #{inspect(worker_name)} shutting down")
      _ ->
        Logger.warning("StreamsReaderWorker #{inspect(worker_name)} terminating: #{inspect(reason)}")
    end
    
    :ok
  end
end
