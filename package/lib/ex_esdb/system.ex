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

  @impl true
  def init(opts) do
    # Support umbrella configuration patterns
    otp_app = Keyword.get(opts, :otp_app, :ex_esdb)
    # Set the configuration context for this process and its children
    Options.set_context(otp_app)

    db_type = Options.db_type(otp_app)

    # Start PubSubSystem first
    pubsub_opts = Keyword.put(opts, :name, :ex_esdb_gater_pubsub)
    children = [
      {ExESDBGater.PubSubSystem, pubsub_opts},
      {ExESDB.CoreSystem, opts}
    ]

    # Conditionally add clustering components based on db_type
    # IMPORTANT: Clustering components are added AFTER core infrastructure
    # to ensure the Store and PersistenceSystem are fully operational before any clustering attempts
    children =
      case db_type do
        :cluster ->
          libcluster_child = LibClusterHelper.maybe_add_libcluster(nil)

          cluster_children =
            [
              libcluster_child,
              # ClusterSystem handles cluster coordination and membership
              {ExESDB.ClusterSystem, opts},
              # GatewaySystem starts LAST to ensure external interface is only available after clustering is ready
              {ExESDB.GatewaySystem, opts}
            ]
            |> Enum.filter(& &1)

          children ++ cluster_children

        :single ->
          # In single-node mode, GatewaySystem can start immediately after CoreSystem
          children ++ [{ExESDB.GatewaySystem, opts}]

        _ ->
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
    IO.puts(Themes.system(self(), msg))
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

  @doc """
  Start ExESDB.System with automatic configuration discovery.

  This function supports several modes:
  1. With explicit opts: `ExESDB.System.start_link(opts)` - uses provided configuration
  2. With OTP app name: `ExESDB.System.start_link(:my_app)` - discovers config from specified app
  3. With empty opts or no args: `ExESDB.System.start_link([])` or `ExESDB.System.start_link()` - discovers config from calling application

  ## Examples

      # Explicit configuration (current approach)
      opts = ExESDB.Options.app_env(:my_app)
      ExESDB.System.start_link(opts)

      # Auto-discovery from specific app
      ExESDB.System.start_link(:my_app)

      # Auto-discovery from calling application
      ExESDB.System.start_link()
  """
  def start_link(opts \\ [])

  def start_link(opts) when is_list(opts) do
    final_opts = resolve_configuration(opts)
    store_id = Keyword.get(final_opts, :store_id)
    name = system_name(store_id)

    Supervisor.start_link(
      __MODULE__,
      final_opts,
      name: name
    )
  end

  def start_link(otp_app) when is_atom(otp_app) do
    opts = Options.app_env(otp_app)
    enhanced_opts = Keyword.put(opts, :otp_app, otp_app)
    start_link(enhanced_opts)
  end

  defp resolve_configuration(opts) do
    if Keyword.has_key?(opts, :otp_app) do
      opts
    else
      otp_app = discover_calling_app() || :ex_esdb
      enhanced_opts = Keyword.put(Options.app_env(otp_app), :otp_app, otp_app)
      enhanced_opts
    end
  end

  defp discover_calling_app do
    # Try multiple strategies to discover the calling application
    try_mix_project() ||
    try_application_controller() ||
    try_loaded_applications() ||
    System.get_env("OTP_APP") |> maybe_atom()
  end

  defp try_mix_project do
    try do
      Mix.Project.config()[:app]
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp try_loaded_applications do
    Application.loaded_applications()
    |> Enum.find(fn {app, _desc, _vsn} ->
      # Look for user applications (not system ones)
      app_str = Atom.to_string(app)
      not String.starts_with?(app_str, "kernel") and
      not String.starts_with?(app_str, "stdlib") and
      app not in [:logger, :runtime_tools, :crypto, :compiler, :elixir, :mix]
    end)
    |> case do
      {app, _, _} -> app
      nil -> nil
    end
  end

  defp maybe_atom(nil), do: nil
  defp maybe_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      _ -> String.to_atom(str)
    end
  end

  # Try to get the OTP app from the application controller
  defp try_application_controller do
    try do
      # Get all running applications and find the one that started most recently
      # that isn't a system application
      :application.which_applications()
      |> Enum.reverse()  # Most recent first
      |> Enum.find(fn {app, _desc, _vsn} ->
        app_str = Atom.to_string(app)
        not String.starts_with?(app_str, "kernel") and
        not String.starts_with?(app_str, "stdlib") and
        app not in [:logger, :runtime_tools, :crypto, :compiler, :elixir, :mix, :ex_esdb]
      end)
      |> case do
        {app, _, _} -> app
        nil -> nil
      end
    rescue
      _ -> nil
    end
  end

  def start(opts) do
    case start_link(opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> raise "failed to start eventstores supervisor: #{inspect(reason)}"
    end
  end

  def child_spec(opts) when is_list(opts) do
    store_id = Keyword.get(opts, :store_id)
    id = system_name(store_id)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
  
  def child_spec(otp_app) when is_atom(otp_app) do
    opts = Options.app_env(otp_app)
    enhanced_opts = Keyword.put(opts, :otp_app, otp_app)
    store_id = Keyword.get(enhanced_opts, :store_id)
    id = system_name(store_id)

    %{
      id: id,
      start: {__MODULE__, :start_link, [otp_app]},
      type: :supervisor
    }
  end
end
