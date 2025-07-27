defmodule ExESDB.MonitoringSystem do
  @moduledoc """
  Supervisor for the Monitoring subsystem.
  
  Manages health checking, performance tracking, and system monitoring components.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    children = [
      {ExESDB.Monitoring.HealthChecker, []},
      {ExESDB.Monitoring.PerformanceTracker, []},
      {ExESDB.SubscriptionHealthTracker, opts}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
