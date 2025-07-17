defmodule ExESDB.SnapshotsWriter do
  @moduledoc """
   The API for interacting with ExESDB Snapshots Writers.
   It functions as an API for SnapshotsWriterWorkers, 
   by requesting a worker from the Cluster. 
   If no worker is available for the specific combination of store, source_uuid, and stream_uuid,
   then a new worker is started.
  """
  def hr_snapshots_writer_name(store_id, source_uuid, stream_uuid),
    do: :"snapshots_writer_#{store_id}_#{source_uuid}_#{stream_uuid}"

  def cluster_id(store, source_uuid, stream_uuid),
    do: {:snapshots_writer, store, source_uuid, stream_uuid}

  @spec worker_pids(
          store :: atom(),
          source_uuid :: binary(),
          stream_uuid :: binary()
        ) :: [pid()]
  defp worker_pids(store, source_uuid, stream_uuid) do
    cluster_id = cluster_id(store, source_uuid, stream_uuid)

    Swarm.registered()
    |> Enum.filter(fn {name, _} ->
      match?(^cluster_id, name)
    end)
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
    key = :erlang.phash2({store, source_uuid, stream_uuid}, partitions)
    key
  end

  defp start_worker(store, source_uuid, stream_uuid) do
    partition = partition_for(store, source_uuid, stream_uuid)
    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsWriters, store)

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {partition_name, partition}},
           {ExESDB.SnapshotsWriterWorker, {store, source_uuid, stream_uuid, partition}}
         ) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start snapshots writer: #{inspect(reason)}"
    end
  end

  @spec record_snapshot(
          store :: atom(),
          source_uuid :: binary(),
          stream_uuid :: binary(),
          version :: integer(),
          snapshot_record :: map()
        ) :: :ok
  def record_snapshot(store, source_uuid, stream_uuid, version, snapshot_record) do
    GenServer.cast(
      get_worker(store, source_uuid, stream_uuid),
      {:record_snapshot, store, source_uuid, stream_uuid, version, snapshot_record}
    )

    :ok
  end

  @spec delete_snapshot(
          store :: atom(),
          source_uuid :: binary(),
          stream_uuid :: binary(),
          version :: integer()
        ) :: :ok
  def delete_snapshot(store, source_uuid, stream_uuid, version) do
    GenServer.cast(
      get_worker(store, source_uuid, stream_uuid),
      {:delete_snapshot, store, source_uuid, stream_uuid, version}
    )

    :ok
  end
end
