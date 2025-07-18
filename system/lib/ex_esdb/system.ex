defmodule ExESDB.System do
  @moduledoc """
    This module is the top level supervisor for the ExESDB system.
    
    It uses a layered supervision architecture for better fault tolerance:
    
    SINGLE NODE MODE:
    1. CoreSystem: Critical infrastructure (PersistenceSystem + NotificationSystem + StoreSystem)
    2. GatewaySystem: External interface with pooled workers
    
    CLUSTER MODE:
    1. CoreSystem: Critical infrastructure (PersistenceSystem + NotificationSystem + StoreSystem)
    2. LibCluster: Node discovery and connection (after core is ready)
    3. ClusterSystem: Cluster coordination and membership
    4. GatewaySystem: External interface (LAST - only after clustering is ready)
    
    NotificationSystem (part of CoreSystem) includes:
    - LeaderSystem: Leadership responsibilities and subscription management
    - EmitterSystem: Event emission and distribution
    
    IMPORTANT: Core functionality (Store, Persistence) must be fully operational 
    before any clustering/membership/registration components start. This ensures 
    the server is ready to handle requests before announcing itself to the cluster.
    
    In cluster mode, GatewaySystem starts LAST to prevent external connections
    until the entire distributed system is properly initialized.
    
    Note: Store management is now handled by the distributed ex-esdb-gater API.
  """
  use Supervisor

  alias ExESDB.Options, as: Options
  alias ExESDB.Themes, as: Themes
  alias ExESDBGater.LibClusterHelper, as: LibClusterHelper

  require Logger
  require Phoenix.PubSub

  @impl true
  def init(opts) do
    # Support umbrella configuration patterns
    otp_app = Keyword.get(opts, :otp_app, :ex_esdb)

    # Set the configuration context for this process and its children
    Options.set_context(otp_app)

    db_type =
      if otp_app != :ex_esdb do
        Options.db_type(otp_app)
      else
        Options.db_type()
      end

    Logger.info("Starting ExESDB in #{db_type} mode")
    Logger.info("Using configuration from OTP app: #{inspect(otp_app)}")

    # Core infrastructure - must start first
    children = [
      {ExESDB.CoreSystem, opts}
    ]

    # Conditionally add clustering components based on db_type
    # IMPORTANT: Clustering components are added AFTER core infrastructure
    # to ensure the Store and PersistenceSystem are fully operational before any clustering attempts
    children =
      case db_type do
        :cluster ->
          Logger.info("Adding clustering components for cluster mode")

          libcluster_child = LibClusterHelper.maybe_add_libcluster(nil)
          Logger.info("LibClusterHelper result: #{inspect(libcluster_child)}")

          cluster_children =
            [
              libcluster_child,
              # ClusterSystem handles cluster coordination and membership
              {ExESDB.ClusterSystem, opts},
              # GatewaySystem starts LAST to ensure external interface is only available after clustering is ready
              {ExESDB.GatewaySystem, opts}
            ]
            |> Enum.filter(& &1)

          Logger.info("Cluster children after filtering: #{inspect(cluster_children)}")

          children ++ cluster_children

        :single ->
          Logger.info("Skipping clustering components for single-node mode")
          # In single-node mode, GatewaySystem can start immediately after CoreSystem
          children ++ [{ExESDB.GatewaySystem, opts}]

        _ ->
          Logger.warning("Unknown db_type: #{inspect(db_type)}, defaulting to single-node mode")
          children ++ [{ExESDB.GatewaySystem, opts}]
      end

    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigquit, :handle)

    spawn(fn -> handle_os_signal() end)

    ret =
      Supervisor.init(
        children,
        strategy: :rest_for_one
      )

    msg = "is UP in #{db_type} mode!"
    IO.puts("#{Themes.system(self(), msg)}")
    ret
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
        IO.puts("Unknown signal: #{inspect(msg)}")
        Logger.warning("Received unknown signal: #{inspect(msg)}")
    end

    handle_os_signal()
  end

  def stop(_reason \\ :normal) do
    Process.sleep(2_000)
    Application.stop(:ex_esdb)
  end

  @doc """
  Generate a store-specific name for this system supervisor.

  This allows multiple ExESDB systems to run on the same node with different stores.

  ## Examples

      iex> ExESDB.System.system_name("my_store")
      :"exesdb_system_my_store"
      
      iex> ExESDB.System.system_name(nil)
      ExESDB.System
  """
  def system_name(store_id) when is_binary(store_id) do
    String.to_atom("exesdb_system_#{store_id}")
  end

  def system_name(store_id) when is_atom(store_id) and not is_nil(store_id) do
    String.to_atom("exesdb_system_#{store_id}")
  end

  def system_name(_), do: __MODULE__

  def start_link(opts) do
    store_id = Keyword.get(opts, :store_id)
    name = system_name(store_id)

    Supervisor.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  def start(opts) do
    case start_link(opts) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start eventstores supervisor: #{inspect(reason)}"
    end
  end

  def child_spec(opts) do
    store_id = Keyword.get(opts, :store_id)
    id = system_name(store_id)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end
