defmodule ExESDB.SnapshotsReader do
  @moduledoc """
    Provides functions for reading snapshots
  """

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
    case worker_pids(store, source_uuid, stream_uuid) do
      [] ->
        start_worker(store, source_uuid, stream_uuid)

      worker_pids ->
        worker_pids
        |> Enum.random()
    end
  end

  defp partition_for(store, source_uuid, stream_uuid) do
    partitions = System.schedulers_online()
    partition = :erlang.phash2({store, source_uuid, stream_uuid}, partitions)
    partition
  end

  def start_worker(store, source_uuid, stream_uuid) do
    partition = partition_for(store, source_uuid, stream_uuid)
    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsReaders, store)

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {partition_name, partition}},
           {ExESDB.SnapshotsReaderWorker, {store, source_uuid, stream_uuid, partition}}
         ) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start snapshots reader: #{inspect(reason)}"
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
