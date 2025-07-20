defmodule ExESDB.ObservationSystem do
  @moduledoc """
  Supervisor for the Observation subsystem.
  
  Manages real-time monitoring, metrics collection, and observation components.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {ExESDB.Observation.MetricsCollector, []},
      {ExESDB.Observation.ProcessMonitor, []},
      {ExESDB.Observation.SystemMonitor, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
