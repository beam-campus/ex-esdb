defmodule ExESDB.StreamsReader do
  @moduledoc """
    This module is responsible for reading events from a stream.
  """

  require Logger

  ########### API ############
  def worker_id(store, stream_id),
    do: {:streams_reader_worker, store, stream_id}

  @doc """
    Returns a list of all streams in the store.
    ## Parameters
      - `store` is the name of the store.
    ## Returns
      - `{:ok, streams}`  if successful.
  """
  @spec get_streams(store :: atom()) :: {:ok, list()} | {:error, term()}
  def get_streams(store) do
    Logger.info("[STREAMS_READER] API: get_streams called for store: #{inspect(store)}")
    
    try do
      reader_pid = get_reader(store, "general_info")
      Logger.info("[STREAMS_READER] API: Calling get_streams on reader PID: #{inspect(reader_pid)}")
      
      result = GenServer.call(reader_pid, {:get_streams, store})
      
      case result do
        {:ok, streams} ->
          Logger.info("[STREAMS_READER] API: ✅ Successfully retrieved #{length(streams)} streams")
          result
        {:error, reason} ->
          Logger.error("[STREAMS_READER] API: ❌ Failed to get streams: #{inspect(reason)}")
          result
      end
    rescue
      error ->
        Logger.error("[STREAMS_READER] API: ❌ Exception in get_streams: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  @doc """
    Streams events from `stream` in batches of `count` events, in a `direction`.
  """
  @spec stream_events(
          store :: atom(),
          stream_id :: any(),
          start_version :: integer(),
          count :: integer(),
          direction :: :forward | :backward
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_events(store, stream_id, start_version, count, direction \\ :forward) do
    Logger.info("[STREAMS_READER] API: stream_events called for store: #{inspect(store)}, stream_id: #{inspect(stream_id)}")
    Logger.info("[STREAMS_READER] API: Parameters - start_version: #{start_version}, count: #{count}, direction: #{direction}")
    
    try do
      reader_pid = get_reader(store, stream_id)
      Logger.info("[STREAMS_READER] API: Calling stream_events on reader PID: #{inspect(reader_pid)}")
      
      result = GenServer.call(
        reader_pid,
        {:stream_events, store, stream_id, start_version, count, direction}
      )
      
      case result do
        {:ok, event_stream} ->
          # For streams, we can't easily count without consuming, so just log success
          Logger.info("[STREAMS_READER] API: ✅ Successfully retrieved event stream")
          result
        {:error, reason} ->
          Logger.error("[STREAMS_READER] API: ❌ Failed to stream events: #{inspect(reason)}")
          result
      end
    rescue
      error ->
        Logger.error("[STREAMS_READER] API: ❌ Exception in stream_events: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp get_reader(store, stream_id) do
    Logger.info("[STREAMS_READER] Getting reader for store: #{inspect(store)}, stream_id: #{inspect(stream_id)}")
    
    case get_cluster_reader(store, stream_id) do
      nil ->
        Logger.info("[STREAMS_READER] No existing reader found, starting new reader")
        start_reader(store, stream_id)

      reader_pid ->
        Logger.info("[STREAMS_READER] ✅ Found existing reader at PID: #{inspect(reader_pid)}")
        reader_pid
    end
  end

  defp get_cluster_reader(store, stream_id) do
    Logger.info("[STREAMS_READER] Searching for existing cluster reader for store: #{inspect(store)}, stream_id: #{inspect(stream_id)}")
    
    case Swarm.registered()
         |> Enum.filter(fn {name, _} ->
           match?({:streams_reader_worker, ^store, ^stream_id}, name)
         end)
         |> Enum.map(fn {_, pid} -> pid end) do
      [] ->
        Logger.info("[STREAMS_READER] No registered cluster readers found")
        nil

      readers ->
        Logger.info("[STREAMS_READER] Found #{length(readers)} registered cluster readers")
        selected_reader = readers |> Enum.random()
        Logger.info("[STREAMS_READER] Selected random reader: #{inspect(selected_reader)}")
        selected_reader
    end
  end

  defp partition_for(store, stream_id) do
    partitions = System.schedulers_online()
    key = :erlang.phash2({store, stream_id}, partitions)
    Logger.info("[STREAMS_READER] Partition calculation: #{partitions} schedulers online, hash key: #{key} for store: #{inspect(store)}, stream_id: #{inspect(stream_id)}")
    key
  end

  defp start_reader(store, stream_id) do
    Logger.info("[STREAMS_READER] Starting new reader for store: #{inspect(store)}, stream_id: #{inspect(stream_id)}")
    
    partition = partition_for(store, stream_id)
    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.StreamsReaders, store)
    
    Logger.info("[STREAMS_READER] Calculated partition: #{partition}")
    Logger.info("[STREAMS_READER] Partition name: #{inspect(partition_name)}")
    Logger.info("[STREAMS_READER] Starting StreamsReaderWorker via DynamicSupervisor...")

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {partition_name, partition}},
           {ExESDB.StreamsReaderWorker, {store, stream_id, partition}}
         ) do
      {:ok, pid} -> 
        Logger.info("[STREAMS_READER] ✅ Successfully started new reader worker at PID: #{inspect(pid)}")
        pid
      {:error, {:already_started, pid}} -> 
        Logger.info("[STREAMS_READER] ✅ Reader worker already started at PID: #{inspect(pid)}")
        pid
      {:error, reason} -> 
        Logger.error("[STREAMS_READER] ❌ Failed to start streams reader: #{inspect(reason)}")
        raise "failed to start streams reader: #{inspect(reason)}"
    end
  end
end
