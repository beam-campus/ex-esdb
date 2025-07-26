defmodule ExESDB.GatewaySystem do
  @moduledoc """
  Supervisor for gateway components providing external interface.

  This supervisor manages a pool of gateway workers for high availability
  and load distribution.

  Components:
  - GatewayWorkers: Pool of GatewayWorkers via PartitionSupervisor
  # PubSub: External communication now handled externally
  """
  use Supervisor

  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  @impl true
  def init(opts) do
    gateway_pool_size = Keyword.get(opts, :gateway_pool_size, 1)
    store_id = StoreNaming.extract_store_id(opts)

    children =
      [
        {PartitionSupervisor,
         child_spec: {ExESDB.GatewayWorker, opts},
         name: StoreNaming.partition_name(ExESDB.GatewayWorkers, store_id),
         partitions: gateway_pool_size},
        # Assuming PubSub initialization occurs externally
      ]
      # Remove nil entries
      |> Enum.filter(& &1)

    IO.puts(
      "#{Themes.gateway_supervisor(self(), "GatewaySystem is UP with #{gateway_pool_size} workers")}"
    )

    # Use :one_for_one because components are independent
    Supervisor.init(children,
      strategy: :one_for_one,
      max_restarts: 15,
      max_seconds: 60
    )
  end

  # PubSub management removed, assuming it's initialized outside of this module

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor
    }
  end
end
