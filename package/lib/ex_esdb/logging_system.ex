defmodule ExESDB.LoggingSystem do
  @moduledoc """
  LoggingSystem supervisor that manages individual logging workers for different ExESDB components.
  
  This system replaces direct terminal output with PubSub-based logging events that can be
  consumed by various logging workers and processed appropriately.
  
  The system publishes logging events to the :ex_esdb_logging PubSub topic with the following structure:
  
  ```elixir
  %{
    component: :emitter_pool | :emitter_worker | :emitter_system,
    event_type: :startup | :shutdown | :action | :health | :error,
    store_id: atom(),
    pid: pid(),
    timestamp: DateTime.t(),
    message: String.t(),
    metadata: map()
  }
  ```
  """
  
  use Supervisor
  require Logger
  
  alias ExESDB.StoreNaming
  
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
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end
  
  @impl Supervisor
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    children = [
      # Emitter-specific logging workers
      {ExESDB.EmitterSystemLoggingWorker, Keyword.put(opts, :store_id, store_id)},
      {ExESDB.EmitterPoolLoggingWorker, Keyword.put(opts, :store_id, store_id)},
      {ExESDB.EmitterWorkerLoggingWorker, Keyword.put(opts, :store_id, store_id)}
    ]
    
    Logger.info("LoggingSystem started for store #{store_id}")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
