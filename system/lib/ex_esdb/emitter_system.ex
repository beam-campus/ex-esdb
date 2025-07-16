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
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.EmitterPools}
    ]

    # Use :one_for_one - simple structure
    res =
      Supervisor.init(children,
        strategy: :one_for_one,
        max_restarts: 10,
        max_seconds: 60
      )

    IO.puts("#{Themes.emitter_system(self(), "is UP")}")
    res
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # Only restart when abnormal
      restart: :transient,
      shutdown: 5_000,
      type: :supervisor
    }
  end
end
