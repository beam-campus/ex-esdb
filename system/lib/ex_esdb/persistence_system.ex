defmodule ExESDB.PersistenceSystem do
  @moduledoc """
  Supervisor for persistence layer components.
  
  This supervisor manages all data persistence components that can
  operate independently of each other.
  
  Components:
  - Streams: Stream read/write operations
  - Snapshots: Snapshot management
  - Subscriptions: Subscription management
  """
  use Supervisor
  
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  @impl true
  def init(opts) do
    children = [
      {ExESDB.Streams, opts},
      {ExESDB.Snapshots, opts},
      {ExESDB.Subscriptions, opts}
    ]

    IO.puts("#{Themes.system(self(), "PersistenceSystem is UP")}")
    
    # Use :one_for_one because these components are independent
    Supervisor.init(children, 
      strategy: :one_for_one,
      max_restarts: 10,
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
