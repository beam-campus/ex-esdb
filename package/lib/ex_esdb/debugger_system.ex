defmodule ExESDB.DebuggerSystem do
  @moduledoc """
  Supervisor for the ExESDB Debugger system.
  
  Manages all debugger subsystems including inspection, monitoring,
  and observation.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {ExESDB.InspectionSystem, []},
      {ExESDB.ObservationSystem, []},
      {ExESDB.MonitoringSystem, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
