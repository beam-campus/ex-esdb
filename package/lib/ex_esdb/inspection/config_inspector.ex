defmodule ExESDB.Inspection.ConfigInspector do
  @moduledoc """
  Inspects configuration settings for the ExESDB system.
  
  Provides functionality to retrieve and analyze system configuration
  across different stores and environments.
  """
  
  use GenServer
  
  alias ExESDB.Options
  
  # API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_config(store_id \\ nil) do
    GenServer.call(__MODULE__, {:get_config, store_id})
  end
  
  def get_environment_config() do
    GenServer.call(__MODULE__, :get_environment_config)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:get_config, store_id}, _from, state) do
    store_id = store_id || discover_store_id()
    otp_app = discover_otp_app(store_id)
    
    config = %{
      store_id: Options.store_id(otp_app),
      data_dir: Options.data_dir(otp_app),
      db_type: Options.db_type(otp_app),
      timeout: Options.timeout(otp_app),
      pub_sub: Options.pub_sub(otp_app),
      reader_idle_ms: Options.reader_idle_ms(otp_app),
      writer_idle_ms: Options.writer_idle_ms(otp_app),
      store_description: Options.store_description(otp_app),
      store_tags: Options.store_tags(otp_app),
      persistence_interval: Options.persistence_interval(otp_app),
      persistence_enabled: Options.persistence_enabled(otp_app),
      topologies: Options.topologies()
    }
    
    {:reply, {:ok, config}, state}
  end
  
  @impl true
  def handle_call(:get_environment_config, _from, state) do
    env_config = %{
      node: node(),
      otp_release: :erlang.system_info(:otp_release),
      elixir_version: System.version(),
      vm_args: :init.get_arguments(),
      environment: Mix.env()
    }
    
    {:reply, {:ok, env_config}, state}
  end
  
  # Private functions
  
  defp discover_store_id do
    Process.registered()
    |> Enum.find(fn name ->
      name_str = Atom.to_string(name)
      String.starts_with?(name_str, "exesdb_system_")
    end)
    |> case do
      nil -> :default_store
      name ->
        name_str = Atom.to_string(name)
        case String.split(name_str, "exesdb_system_") do
          ["", store_id] -> String.to_atom(store_id)
          _ -> :default_store
        end
    end
  end
  
  defp discover_otp_app(store_id) do
    case Application.loaded_applications() do
      apps when is_list(apps) ->
        apps
        |> Enum.find(fn {app, _, _} ->
          config = Application.get_env(app, :ex_esdb, [])
          Keyword.get(config, :store_id) == store_id
        end)
        |> case do
          {app, _, _} -> app
          nil -> :ex_esdb
        end
      _ -> :ex_esdb
    end
  end
end
