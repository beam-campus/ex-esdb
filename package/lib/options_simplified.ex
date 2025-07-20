defmodule ExESDB.Options.Simplified do
  @moduledoc """
  Simplified ExESDB configuration module using automatic OTP app discovery.
  
  This module dramatically reduces complexity by:
  1. Automatically discovering the calling application
  2. Using a macro to generate config functions with less duplication
  3. Providing sensible defaults and environment variable overrides
  
  Usage:
    # Automatic discovery (recommended)
    ExESDB.Options.data_dir()      # Discovers calling app automatically
    
    # Explicit app specification
    ExESDB.Options.data_dir(:my_app)
    
    # Context-based (for umbrella apps)
    ExESDB.Options.with_context(:my_app, fn ->
      ExESDB.Options.data_dir()    # Uses :my_app context
    end)
  """
  
  # Environment variable mappings
  @env_mappings %{
    data_dir: "EX_ESDB_DATA_DIR",
    store_id: "EX_ESDB_STORE_ID",
    timeout: "EX_ESDB_TIMEOUT",
    db_type: "EX_ESDB_DB_TYPE",
    pub_sub: "EX_ESDB_PUB_SUB",
    writer_idle_ms: "EX_ESDB_WRITER_IDLE_MS",
    reader_idle_ms: "EX_ESDB_READER_IDLE_MS",
    store_description: "EX_ESDB_STORE_DESCRIPTION",
    store_tags: "EX_ESDB_STORE_TAGS",
    persistence_interval: "EX_ESDB_PERSISTENCE_INTERVAL",
    persistence_enabled: "EX_ESDB_PERSISTENCE_ENABLED"
  }

  # Configuration defaults
  @defaults %{
    data_dir: "/data",
    store_id: :undefined,
    timeout: 10_000,
    db_type: :single,
    pub_sub: :ex_esdb_pubsub,
    writer_idle_ms: 10_000,
    reader_idle_ms: 10_000,
    store_description: "undefined!",
    store_tags: [],
    persistence_interval: 5_000,
    persistence_enabled: true
  }

  #
  # App Discovery Functions
  #

  @doc """
  Discovers the current OTP application name using multiple strategies.
  """
  def discover_app_name do
    Process.get(:ex_esdb_otp_app) ||
    try_mix_project() ||
    System.get_env("OTP_APP") |> maybe_atom() ||
    try_loaded_applications() ||
    :ex_esdb
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
      app not in [:logger, :runtime_tools, :crypto, :compiler]
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

  #
  # Context Management
  #

  @doc "Set application context for configuration lookup"
  def set_context(otp_app) when is_atom(otp_app) do
    Process.put(:ex_esdb_otp_app, otp_app)
  end

  @doc "Get current application context"
  def get_context, do: Process.get(:ex_esdb_otp_app)

  @doc "Execute function within specific application context"
  def with_context(otp_app, fun) when is_atom(otp_app) and is_function(fun, 0) do
    previous_context = Process.get(:ex_esdb_otp_app)
    Process.put(:ex_esdb_otp_app, otp_app)

    try do
      fun.()
    after
      if previous_context do
        Process.put(:ex_esdb_otp_app, previous_context)
      else
        Process.delete(:ex_esdb_otp_app)
      end
    end
  end

  #
  # Configuration Access Functions
  #

  @doc "Get complete configuration for an OTP app"
  def app_env(otp_app \\ nil) do
    app = otp_app || discover_app_name()
    config = Application.get_env(app, :ex_esdb, [])
    Keyword.put(config, :otp_app, app)
  end

  # Note: Individual config functions are defined manually below
  # to avoid macro complexity while still reducing duplication

  @doc """
  Generic configuration value getter with automatic app discovery.
  
  Priority order:
  1. Environment variable
  2. Application configuration
  3. Default value
  """
  def get_config_value(key, otp_app \\ nil) do
    app = otp_app || get_context() || discover_app_name()
    
    case get_env_value(key) do
      nil -> get_app_config_value(app, key)
      env_value -> transform_env_value(key, env_value)
    end
  end

  defp get_env_value(key) do
    env_var = Map.get(@env_mappings, key)
    env_var && System.get_env(env_var)
  end

  defp get_app_config_value(app, key) do
    default = Map.get(@defaults, key)
    Application.get_env(app, :ex_esdb, [])
    |> Keyword.get(key, default)
  end

  # Transform environment string values to appropriate types
  defp transform_env_value(:timeout, value), do: String.to_integer(value)
  defp transform_env_value(:writer_idle_ms, value), do: String.to_integer(value)
  defp transform_env_value(:reader_idle_ms, value), do: String.to_integer(value)
  defp transform_env_value(:persistence_interval, value), do: String.to_integer(value)
  defp transform_env_value(:persistence_enabled, value), do: String.to_atom(value)
  defp transform_env_value(:db_type, value), do: String.to_atom(value)
  defp transform_env_value(:store_id, value), do: to_unique_atom(value)
  defp transform_env_value(:pub_sub, value), do: to_unique_atom(value)
  defp transform_env_value(:store_tags, value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  defp transform_env_value(_key, value), do: value

  defp to_unique_atom(candidate) do
    try do
      String.to_existing_atom(candidate)
    rescue
      _ -> String.to_atom(candidate)
    end
  end

  #
  # Individual Configuration Functions
  #

  def data_dir(otp_app \\ nil), do: get_config_value(:data_dir, otp_app)
  def store_id(otp_app \\ nil), do: get_config_value(:store_id, otp_app)
  def timeout(otp_app \\ nil), do: get_config_value(:timeout, otp_app)
  def db_type(otp_app \\ nil), do: get_config_value(:db_type, otp_app)
  def pub_sub(otp_app \\ nil), do: get_config_value(:pub_sub, otp_app)
  def writer_idle_ms(otp_app \\ nil), do: get_config_value(:writer_idle_ms, otp_app)
  def reader_idle_ms(otp_app \\ nil), do: get_config_value(:reader_idle_ms, otp_app)
  def store_description(otp_app \\ nil), do: get_config_value(:store_description, otp_app)
  def store_tags(otp_app \\ nil), do: get_config_value(:store_tags, otp_app)
  def persistence_interval(otp_app \\ nil), do: get_config_value(:persistence_interval, otp_app)
  def persistence_enabled(otp_app \\ nil), do: get_config_value(:persistence_enabled, otp_app)

  # Additional convenience functions
  def topologies, do: Application.get_env(:libcluster, :topologies)

  @doc """
  Get a specific config value from app environment with default.
  """
  def app_env(otp_app, key, default) when is_atom(otp_app) and is_atom(key) do
    Keyword.get(app_env(otp_app), key, default)
  end
end
