defmodule ExESDB.System do
  @moduledoc """
    This module is the top level supervisor for the ExESDB system.
    
    It uses a fully reactive, event-driven architecture where:
    
    1. ControlSystem: Event coordination infrastructure (PubSub + ControlPlane)
    2. All other systems: Start in parallel and report readiness via events
    
    ## Reactive Design Principles:
    
    - **No cluster/single distinction**: All systems start uniformly and adapt based on discovery
    - **Parallel startup**: Systems start independently and report readiness asynchronously  
    - **Event-driven coordination**: Control Plane orchestrates via pub/sub events
    - **Self-organizing**: Nodes discover each other and emit cluster events
    
    ## System Lifecycle:
    
    1. ControlSystem starts first (PubSub + ControlPlane)
    2. All other systems start in parallel:
       - PersistenceSystem
       - NotificationSystem  
       - StoreSystem
       - ClusterSystem (handles node discovery)
       - GatewaySystem
    3. Systems report readiness to ControlPlane via events
    4. ControlPlane coordinates system-wide readiness
    
    ## Node Discovery & Clustering:
    
    - ClusterSystem always starts (handles both single and cluster modes)
    - LibCluster integration for automatic node discovery
    - Nodes emit events when joining/leaving cluster
    - Other systems react to cluster membership changes
    
    Note: This reactive design eliminates startup race conditions and 
    provides better fault tolerance through event-driven coordination.
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

    # Reactive architecture - all systems start in parallel after ControlSystem
    # No cluster/single distinction - systems adapt based on node discovery events
    libcluster_child = LibClusterHelper.maybe_add_libcluster(nil)
    
    children = [
      # ControlSystem MUST start first - provides event coordination infrastructure
      {ExESDB.ControlSystem, opts},
      
      # All other systems start in parallel and report readiness via events
      {ExESDB.PersistenceSystem, opts},
      {ExESDB.NotificationSystem, opts}, 
      {ExESDB.StoreSystem, opts},
      {ExESDB.ClusterSystem, opts},
      {ExESDB.GatewaySystem, opts}
    ]
    |> maybe_add_libcluster(libcluster_child)

    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigquit, :handle)

    spawn(fn -> handle_os_signal() end)

    ret =
      Supervisor.init(
        children,
        strategy: :one_for_one  # Changed to one_for_one for better fault isolation
      )

    IO.puts(Themes.system(self(), "is UP in reactive mode!"))
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
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
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
  
  # Helper function to conditionally add LibCluster to children
  defp maybe_add_libcluster(children, nil), do: children
  defp maybe_add_libcluster(children, libcluster_child), do: children ++ [libcluster_child]
end
