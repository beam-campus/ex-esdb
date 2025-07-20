defmodule ExESDB.Streams do
  @moduledoc """
    The ExESDB Streams SubSystem.
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
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: StoreNaming.partition_name(ExESDB.StreamsWriters, store_id)},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: StoreNaming.partition_name(ExESDB.StreamsReaders, store_id)}
    ]

    ret = Supervisor.init(children, strategy: :one_for_one)
    IO.puts("#{Themes.streams(self(), "is UP.")}")
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
end
