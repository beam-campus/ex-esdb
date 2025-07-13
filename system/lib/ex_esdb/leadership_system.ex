defmodule ExESDB.LeadershipSystem do
  @moduledoc """
  Supervisor for leadership and event emission components.
  
  This supervisor manages components that are only active when this node
  is the cluster leader. Uses :rest_for_one because EmitterSystem depends
  on LeaderSystem.
  
  Components:
  - LeaderSystem: Leader election and management
  - EmitterSystem: Event emission (depends on leadership)
  """
  use Supervisor
  
  alias ExESDB.Themes, as: Themes

  @impl true
  def init(opts) do
    children = [
      # LeaderSystem must start first
      {ExESDB.LeaderSystem, opts},
      # EmitterSystem depends on leadership
      {ExESDB.EmitterSystem, opts}
    ]

    IO.puts("#{Themes.leader_system(self(), "LeadershipSystem is UP")}")
    
    # Use :rest_for_one because EmitterSystem depends on LeaderSystem
    Supervisor.init(children, 
      strategy: :rest_for_one,
      max_restarts: 5,
      max_seconds: 30
    )
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,  # Can restart on normal shutdown
      shutdown: :infinity,
      type: :supervisor
    }
  end
end
