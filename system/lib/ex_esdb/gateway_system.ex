defmodule ExESDB.GatewaySystem do
  @moduledoc """
  Supervisor for gateway components providing external interface.

  This supervisor manages a pool of gateway workers for high availability
  and load distribution.

  Components:
  - GatewayWorkers: Pool of GatewayWorkers via PartitionSupervisor
  - PubSub: External communication (conditional)
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
        add_pub_sub(opts)
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

  defp add_pub_sub(opts) do
    pub_sub = Keyword.get(opts, :pub_sub)

    case pub_sub do
      nil ->
        add_pub_sub([pub_sub: :native] ++ opts)

      :native ->
        {ExESDB.PubSub, opts}

      pub_sub ->
        # Use PubSubManager to conditionally start Phoenix.PubSub
        case BCUtils.PubSubManager.maybe_child_spec(pub_sub) do
          nil ->
            # PubSub already running, create a dummy child
            %{
              id: :dummy_pubsub,
              start: {Task, :start_link, [fn -> :ok end]},
              restart: :temporary
            }

          child_spec ->
            child_spec
        end
    end
  end

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
