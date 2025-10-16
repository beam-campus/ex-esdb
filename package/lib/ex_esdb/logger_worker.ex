defmodule ExESDB.LoggerWorker do
  @moduledoc """
  LoggerWorker subscribes to events for a specific subsystem and logs events for monitoring and debugging.
  
  Each subsystem should supervise its own LoggerWorker to provide dedicated logging
  for that subsystem's events and operations.
  """
  use GenServer

  require Logger
  alias ExESDB.StoreNaming

  @doc """
  Starts the LoggerWorker for a specific subsystem.
  
  ## Parameters
  - opts: Configuration options including store_id and subsystem_name
  """
  def start_link(opts) do
    subsystem_name = Keyword.get(opts, :subsystem_name)
    store_id = StoreNaming.extract_store_id(opts)
    # Create unique name combining store_id and subsystem
    unique_id = "#{store_id}_#{subsystem_name}"
    name = StoreNaming.genserver_name(__MODULE__, unique_id)
    
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    subsystem_name = Keyword.get(opts, :subsystem_name)
    store_id = StoreNaming.extract_store_id(opts)
    
    Logger.info("LoggerWorker for #{subsystem_name} (store: #{store_id}) starting")
    
    # Note: Event subscription functionality has been removed
    # LoggerWorker will rely on direct logging from other modules
    
    {:ok, %{subsystem: subsystem_name, store_id: store_id}}
  end


  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def child_spec(opts) do
    subsystem_name = Keyword.get(opts, :subsystem_name)
    store_id = StoreNaming.extract_store_id(opts)
    # Create unique id combining store_id and subsystem
    unique_id = "#{store_id}_#{subsystem_name}"
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, unique_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end
end

