defmodule ExESDB.SnapshotsReader do
  @moduledoc """
    Provides functions for reading snapshots
  """

  require Logger
  
  def hr_snapshots_reader_name(store_id, source_uuid, stream_uuid),
    do: :"#{store_id}_#{source_uuid}_#{stream_uuid}_snaps_rdr"

  def cluster_id(store, source_uuid, stream_uuid),
    do: {:snaps_reader, store, source_uuid, stream_uuid}

  @spec worker_pids(
          store :: atom(),
          source_uuid :: binary(),
          stream_uuid :: binary()
        ) :: [pid()]
  defp worker_pids(store, source_uuid, stream_uuid) do
    cluster_id = cluster_id(store, source_uuid, stream_uuid)

    Swarm.registered()
    |> Enum.filter(fn {name, _} -> match?(^cluster_id, name) end)
    |> Enum.map(fn {_, pid} -> pid end)
  end

  @spec get_worker(
          store :: atom(),
          source_uuid :: binary(),
          stream_uuid :: binary()
        ) :: pid()
  defp get_worker(store, source_uuid, stream_uuid) do
    Logger.info("[SNAPSHOTS_READER] Getting worker for store: #{inspect(store)}, source_uuid: #{inspect(source_uuid)}, stream_uuid: #{inspect(stream_uuid)}")
    
    case worker_pids(store, source_uuid, stream_uuid) do
      [] ->
        Logger.info("[SNAPSHOTS_READER] No existing workers found, starting new worker")
        start_worker(store, source_uuid, stream_uuid)

      worker_pids ->
        Logger.info("[SNAPSHOTS_READER] Found #{length(worker_pids)} existing workers")
        selected_worker = worker_pids |> Enum.random()
        Logger.info("[SNAPSHOTS_READER] ✅ Selected worker: #{inspect(selected_worker)}")
        selected_worker
    end
  end

  defp partition_for(store, source_uuid, stream_uuid) do
    partitions = System.schedulers_online()
    partition = :erlang.phash2({store, source_uuid, stream_uuid}, partitions)
    Logger.info("[SNAPSHOTS_READER] Calculated partition #{partition} for store: #{inspect(store)}, source_uuid: #{inspect(source_uuid)}, stream_uuid: #{inspect(stream_uuid)}")
    partition
  end

  def start_worker(store, source_uuid, stream_uuid) do
    Logger.info("[SNAPSHOTS_READER] Starting new worker for store: #{inspect(store)}, source_uuid: #{inspect(source_uuid)}, stream_uuid: #{inspect(stream_uuid)}")
    
    partition = partition_for(store, source_uuid, stream_uuid)
    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsReaders, store)
    
    Logger.info("[SNAPSHOTS_READER] Partition name: #{inspect(partition_name)}")
    Logger.info("[SNAPSHOTS_READER] Starting SnapshotsReaderWorker via DynamicSupervisor...")

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {partition_name, partition}},
           {ExESDB.SnapshotsReaderWorker, {store, source_uuid, stream_uuid, partition}}
         ) do
      {:ok, pid} -> 
        Logger.info("[SNAPSHOTS_READER] ✅ Successfully started new worker at PID: #{inspect(pid)}")
        pid
      {:error, {:already_started, pid}} -> 
        Logger.info("[SNAPSHOTS_READER] ✅ Worker already started at PID: #{inspect(pid)}")
        pid
      {:error, reason} -> 
        Logger.error("[SNAPSHOTS_READER] ❌ Failed to start snapshots reader: #{inspect(reason)}")
        raise "failed to start snapshots reader: #{inspect(reason)}"
    end
  end

  @doc """

  ## Description

    Reads a snapshot version from the store 
    for the given source and stream uuids

  ## Parameters

     * `store` - the store to read from
     * `source_uuid` - the source uuid
     * `stream_uuid` - the stream uuid
     * `version` - the version of the snapshot to read

  ## Returns

     * `{:ok, map()}` - the snapshot
  """
  @spec read_snapshot(
          store :: atom(),
          source_uuid :: binary(),
          stream_uuid :: binary(),
          version :: non_neg_integer()
        ) :: {:ok, map()} | {:error, term()}
  def read_snapshot(store, source_uuid, stream_uuid, version) do
    GenServer.call(
      get_worker(store, source_uuid, stream_uuid),
      {:read_snapshot, store, source_uuid, stream_uuid, version}
    )
  end

  @spec list_snapshots(
          store :: atom(),
          source_uuid :: binary() | :any,
          stream_uuid :: binary() | :any
        ) :: {:ok, [map()]} | {:error, term()}
  def list_snapshots(store, source_uuid \\ :any, stream_uuid \\ :any) do
    GenServer.call(
      get_worker(store, source_uuid, stream_uuid),
      {:list_snapshots, store, source_uuid, stream_uuid}
    )
  end
end
