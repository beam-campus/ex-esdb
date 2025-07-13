defmodule ExESDB.EmitterSystem do
  @moduledoc """
  Supervisor for event emission components.
  
  This supervisor manages the emitter pools that handle event distribution
  to subscribers. Only active when this node is the cluster leader.
  
  Components:
  - EmitterPools: PartitionSupervisor managing dynamic emitter pools
  """
  use Supervisor
  
  alias ExESDB.Themes, as: Themes

  @impl true
  def init(_opts) do
    children = [
      {PartitionSupervisor, 
       child_spec: DynamicSupervisor, 
       name: ExESDB.EmitterPools}
    ]

    IO.puts("#{Themes.emitter_pool(self(), "is UP")}")
    
    # Use :one_for_one - simple structure
    Supervisor.init(children, 
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,  # Only restart when abnormal
      shutdown: 5_000,
      type: :supervisor
    }
  end
end
