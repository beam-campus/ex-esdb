defmodule ExESDB.ScenarioSystem do
  @moduledoc """
  Supervisor for the Scenario subsystem.
  
  Manages scenario execution, configuration loading, and testing orchestration.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {ExESDB.Scenario.ConfigLoader, []},
      {ExESDB.Scenario.Manager, []},
      {ExESDB.Scenario.Executor, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
