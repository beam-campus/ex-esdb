defmodule ExESDB.InspectionSystem do
  @moduledoc """
  Supervisor for the Inspection subsystem.
  
  Manages all process, configuration, and supervision tree inspection components.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {ExESDB.Inspection.ProcessInspector, []},
      {ExESDB.Inspection.ConfigInspector, []},
      {ExESDB.Inspection.TreeInspector, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
