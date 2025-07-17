defmodule ExESDB.Snapshots do
  @moduledoc """
    The ExESDB Snapshots SubSystem.
  """
  use Supervisor

  require Logger
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming


  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    Supervisor.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  @impl true
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    children = [
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: StoreNaming.partition_name(ExESDB.SnapshotsWriters, store_id)},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: StoreNaming.partition_name(ExESDB.SnapshotsReaders, store_id)}
    ]

    ret = Supervisor.init(children, strategy: :one_for_one)
    IO.puts("#{Themes.snapshots_system(self(), "is UP.")}")
    ret
  end

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end

  @doc """
  ## Description
    Returns the key for a snapshot as a Khepri Path.
  ## Examples
      iex> ExESDB.Snapshots.path("source_uuid", "stream_uuid", 1)
      [:snapshots, "source_uuid", "stream_uuid", "000000001"]
  """
  @spec path(
          source_uuid :: String.t(),
          stream_uuid :: String.t(),
          version :: non_neg_integer()
        ) :: list()
  def path(source_uuid, stream_uuid, version)
      when is_binary(source_uuid) and
             is_binary(stream_uuid) and
             is_integer(version) and
             version >= 0 do
    padded_version =
      version
      |> Integer.to_string()
      |> String.pad_leading(10, "0")

    [:snapshots, source_uuid, stream_uuid, padded_version]
  end
end
