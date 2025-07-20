defmodule ExESDB.GatewaySupervisor do
  @moduledoc """
    @deprecated "Use ExESDB.GatewaySystem instead"
    
    The GatewaySupervisor is responsible for starting and supervising the
    GatewayWorkers.
    
    This module is deprecated in favor of ExESDB.GatewaySystem which provides
    improved fault tolerance with pooled workers.
  """
  use Supervisor
  require Logger
  alias ExESDB.Themes, as: Themes

  @impl Supervisor
  def init(opts) do
    children =
      [
        {ExESDB.GatewayWorker, opts}
      ]

    IO.puts("#{Themes.gateway_supervisor(self(), "is UP!")}")
    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_link(opts) do
    store_id = ExESDB.StoreNaming.extract_store_id(opts)
    name = ExESDB.StoreNaming.genserver_name(__MODULE__, store_id)
    
    Supervisor.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  def child_spec(opts) do
    store_id = ExESDB.StoreNaming.extract_store_id(opts)
    
    %{
      id: ExESDB.StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
