defmodule ExESDB.StoreSystem do
  @moduledoc """
  Supervisor for store-related components.

  This supervisor manages the store lifecycle and clustering components.
  Uses :rest_for_one strategy to ensure proper startup order.

  Startup order (critical for distributed coordination):
  1. Store: Core store GenServer - must be fully operational first
  2. StoreCluster: Clustering coordination - depends on Store being ready
  3. StoreRegistry: Distributed store registry - starts after Store system is stable

  This order ensures StoreRegistry only announces a store that is actually ready
  to handle requests, preventing race conditions in distributed environments.
  """
  use Supervisor

  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  @impl true
  def init(opts) do
    children = [
      # Store must start first as other components depend on it
      {ExESDB.Store, opts},
      # StoreCluster handles clustering coordination and depends on Store
      {ExESDB.StoreCluster, opts},
      # StoreRegistry comes last - only starts after Store system is fully operational
      {ExESDB.StoreRegistry, opts}
    ]

    IO.puts("#{Themes.system(self(), "StoreSystem is UP")}")

    # Use :rest_for_one because each component depends on the previous ones
    # StoreCluster depends on Store, StoreRegistry depends on both
    Supervisor.init(children,
      strategy: :rest_for_one,
      max_restarts: 5,
      max_seconds: 30
    )
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
