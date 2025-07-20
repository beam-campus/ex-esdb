defmodule ExESDB.StreamsWriter do
  @moduledoc """
    This module is responsible for writing events to a stream.
    It is actually an API style wrapper around the StreamsWriterWorker.
  """

  ########### API ############
  @spec append_events(
          store :: atom(),
          stream_id :: any(),
          expected_version :: integer(),
          events :: list()
        ) :: {:ok, integer()} | {:error, term()}
  def append_events(store, stream_id, expected_version, events) do
    GenServer.call(
      get_writer(store, stream_id),
      {:append_events, store, stream_id, expected_version, events},
      :infinity
    )
  end

  def worker_id(store, stream_id),
    do: {:streams_writer_worker, store, stream_id}

  def hr_worker_id_atom(store, stream_id),
    do: :"streams_writer_worker_#{store}_#{stream_id}"

  defp get_writer(store, stream_id) do
    case Swarm.registered()
         |> Enum.filter(fn {name, _} ->
           match?({:streams_writer_worker, ^store, ^stream_id}, name)
         end)
         |> Enum.map(fn {_, pid} -> pid end) do
      [] ->
        start_writer(store, stream_id)

      writers ->
        writers
        |> Enum.random()
    end
  end

  defp partition_for(store, stream_id) do
    partitions = System.schedulers_online()
    key = :erlang.phash2({store, stream_id}, partitions)
    key
  end

  defp start_writer(store, stream_id) do
    partition = partition_for(store, stream_id)
    partition_name = ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, store)

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {partition_name, partition}},
           {ExESDB.StreamsWriterWorker, {store, stream_id, partition}}
         ) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start streams writer: #{inspect(reason)}"
    end
  end
end
