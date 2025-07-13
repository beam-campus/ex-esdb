defmodule ExESDB.System do
  @moduledoc """
    This module is the top level supervisor for the ExESDB system.
    It is responsible for supervising:
    - The PubSub mechanism
    - the Event Store (starts and stops khepri)
    - the Cluster (joins and leaves the cluster)
    - the Leader (manages Ra leader-specific functionality)
    - the Subscriptions Supervisor (manages subscriptions)
  """
  use Supervisor

  alias ExESDB.Options, as: Options
  alias BCUtils.PubSubManager

  require Logger
  require Phoenix.PubSub

  @impl true
  def init(opts) do
    db_type = Options.db_type()

    Logger.info("Starting ExESDB in #{db_type} mode")

    children = [
      add_pub_sub(opts),
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.EmitterPools},
      {ExESDB.StoreManager, opts},
      {ExESDB.Streams, opts},
      {ExESDB.Snapshots, opts},
      {ExESDB.Subscriptions, opts},
      {ExESDB.LeaderSystem, opts},
      # Always include KhepriCluster - it's mode-aware
      {ExESDB.KhepriCluster, opts},
      {ExESDB.GatewaySupervisor, opts}
    ]

    # Conditionally add clustering components based on db_type
    children =
      case db_type do
        :cluster ->
          topologies = Options.topologies()
          Logger.info("Adding clustering components for cluster mode")

          [
            {Cluster.Supervisor, [topologies, [name: ExESDB.LibCluster]]},
            {ExESDB.ClusterSystem, opts}
          ] ++ children

        :single ->
          Logger.info("Skipping clustering components for single-node mode")
          children

        _ ->
          Logger.warning("Unknown db_type: #{inspect(db_type)}, defaulting to single-node mode")
          children
      end

    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigquit, :handle)

    spawn(fn -> handle_os_signal() end)

    ret =
      Supervisor.init(
        children,
        strategy: :one_for_one
      )

    Logger.info("System started", pid: self(), mode: db_type)
    ret
  end

  defp add_pub_sub(opts) do
    pub_sub = Keyword.get(opts, :pub_sub)

    case pub_sub do
      nil ->
        add_pub_sub([pub_sub: :native] ++ opts)

      :native ->
        {ExESDB.PubSub, opts}

      pub_sub ->
        # Use PubSubManager to conditionally start Phoenix.PubSub
        case PubSubManager.maybe_child_spec(pub_sub) do
          nil ->
            # PubSub already running, create a dummy child that does nothing
            %{
              id: :dummy_pubsub,
              start: {Task, :start_link, [fn -> :ok end]},
              restart: :temporary
            }

          child_spec ->
            child_spec
        end
    end
  end

  defp handle_os_signal do
    receive do
      {:signal, :sigterm} ->
        Logger.warning("SIGTERM received. Stopping ExESDB")
        stop(:sigterm)

      {:signal, :sigquit} ->
        Logger.warning("SIGQUIT received. Stopping ExESDB")
        stop(:sigquit)

      msg ->
        Logger.warning("Unknown signal received", signal: msg)
        Logger.warning("Received unknown signal: #{inspect(msg)}")
    end

    handle_os_signal()
  end

  def stop(_reason \\ :normal) do
    Process.sleep(2_000)
    Application.stop(:ex_esdb)
  end

  def start_link(opts),
    do:
      Supervisor.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  def start(opts) do
    case start_link(opts) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start eventstores supervisor: #{inspect(reason)}"
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  defp store(opts), do: Keyword.get(opts, :store, Options.store_id())
end
