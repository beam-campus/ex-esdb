defmodule ExESDB.EmitterSystem do
  @moduledoc """
  Supervisor for event emission components.

  This supervisor manages the emitter pools that handle event distribution
  to subscribers. Only active when this node is the cluster leader.

  Components:
  - EmitterPools: PartitionSupervisor managing dynamic emitter pools
  """
  use Supervisor

  alias ExESDB.StoreNaming
  alias ExESDB.LoggingPublisher

  @impl true
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)

    children = [
      {PartitionSupervisor,
       child_spec: DynamicSupervisor,
       name: StoreNaming.partition_name(ExESDB.EmitterPools, store_id)}
    ]

    # Use :one_for_one - simple structure
    res =
      Supervisor.init(children,
        strategy: :one_for_one,
        max_restarts: 10,
        max_seconds: 60
      )

    # Publish startup event instead of direct terminal output
    LoggingPublisher.startup(
      :emitter_system,
      store_id,
      "EMITTER SYSTEM ACTIVATION",
      %{
        store: store_id,
        components: length(children),
        max_restarts: "10/60s"
      }
    )

    res
  end

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
      # Only restart when abnormal
      restart: :transient,
      shutdown: 5_000,
      type: :supervisor
    }
  end
end
