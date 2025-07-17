defmodule ExESDB.ClusterSystem do
  @moduledoc """
  Supervisor for cluster coordination components.

  This supervisor manages cluster-specific coordination components:
  - ClusterCoordinator: Handles coordination logic and split-brain prevention
  - NodeMonitor: Monitors node health and handles failures

  Note: KhepriCluster is managed at the System level since it's mode-aware.
  """
  use Supervisor

  alias ExESDB.StoreNaming, as: StoreNaming
  alias ExESDB.Themes, as: Themes

  defp store_id(opts) do
    Keyword.get(opts, :store_id, :ex_esdb)
  end

  @impl true
  def init(opts) do
    children = [
      # ClusterCoordinator handles coordination logic and split-brain prevention
      {ExESDB.StoreCoordinator, opts},
      # NodeMonitor provides fast failure detection
      {ExESDB.NodeMonitor, node_monitor_config(opts)}
    ]

    IO.puts("#{Themes.cluster_system(self(), "is UP")}")

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_link(opts) do
    Supervisor.start_link(
      __MODULE__,
      opts,
      name: StoreNaming.genserver_name(__MODULE__, store_id(opts))
    )
  end

  def child_spec(opts) do
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id(opts)),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  # Helper function to configure NodeMonitor options
  defp node_monitor_config(opts) do
    store_id = store_id(opts)

    # More lenient configuration for node monitoring to prevent cascading failures
    [
      store_id: store_id,
      # 5 seconds (less frequent probing)
      probe_interval: 5_000,
      # 6 consecutive failures (more tolerance)
      failure_threshold: 6,
      # 3 second timeout per probe (more time)
      probe_timeout: 3_000
    ]
  end
end
