defmodule ExESDB.CoreSystem do
  @moduledoc """
  Critical infrastructure supervisor that manages core ExESDB components.

  This supervisor uses :one_for_all strategy because these components are 
  tightly coupled and must restart together to maintain consistency.

  Startup order:
  1. PersistenceSystem: Manages streams, snapshots, and subscriptions (foundation)
  2. NotificationSystem: Manages leadership and event emission (depends on persistence)
  3. StoreSystem: Manages store lifecycle and clustering (depends on persistence & notification)

  The NotificationSystem includes:
  - LeaderSystem: Leadership responsibilities and subscription management
  - EmitterSystem: Event emission and distribution

  This ensures that leadership and event distribution are core capabilities
  available in both single-node and cluster modes.
  """
  use Supervisor

  require Logger
  
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  @impl true
  def init(opts) do
    children = [
      {ExESDB.PersistenceSystem, opts},
      {ExESDB.NotificationSystem, opts},
      {ExESDB.StoreSystem, opts}
    ]

    IO.puts(Themes.core_system(self(), "is UP"))

    # Use :one_for_all because these components are interdependent
    Supervisor.init(children,
      strategy: :one_for_all,
      max_restarts: 3,
      max_seconds: 60
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
