defmodule ExESDB.StreamsReader do
  @moduledoc """
    This module is responsible for reading events from a stream.
  """

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
  def get_streams(store),
    do:
      GenServer.call(
        get_reader(store, "general_info"),
        {:get_streams, store}
      )

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
  def stream_events(store, stream_id, start_version, count, direction \\ :forward),
    do:
      GenServer.call(
        get_reader(store, stream_id),
        {:stream_events, store, stream_id, start_version, count, direction}
      )

  defp get_reader(store, stream_id) do
    case get_cluster_reader(store, stream_id) do
      nil ->
        start_reader(store, stream_id)

      reader_pid ->
        reader_pid
    end
  end

  defp get_cluster_reader(store, stream_id) do
    case Swarm.registered()
         |> Enum.filter(fn {name, _} ->
           match?({:streams_reader_worker, ^store, ^stream_id}, name)
         end)
         |> Enum.map(fn {_, pid} -> pid end) do
      [] ->
        nil

      readers ->
        readers
        |> Enum.random()
    end
  end

  defp partition_for(store, stream_id) do
    partitions = System.schedulers_online()
    key = :erlang.phash2({store, stream_id}, partitions)
    key
  end

  defp start_reader(store, stream_id) do
    partition = partition_for(store, stream_id)
    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.StreamsReaders, store)

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {partition_name, partition}},
           {ExESDB.StreamsReaderWorker, {store, stream_id, partition}}
         ) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start streams reader: #{inspect(reason)}"
    end
  end
end
