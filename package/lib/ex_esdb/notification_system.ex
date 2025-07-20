defmodule ExESDB.NotificationSystem do
  @moduledoc """
  Supervisor for event notification and distribution components.

  This supervisor manages the core event notification functionality:
  - LeaderSystem: Leadership responsibilities and subscription management
  - EmitterSystem: Event emission and distribution

  This is a core component that runs in both single-node and cluster modes.
  The leadership determination happens at the store level, not the clustering level.
  """
  use Supervisor

  require Logger
  
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  @impl true
  def init(opts) do
    children = [
      # LeaderSystem handles leadership responsibilities
      {ExESDB.LeaderSystem, opts},
      # EmitterSystem handles event distribution
      {ExESDB.EmitterSystem, opts}
    ]

    IO.puts("#{Themes.notification_system(self(), "is UP")}")

    # Use :rest_for_one because EmitterSystem depends on LeaderSystem
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
