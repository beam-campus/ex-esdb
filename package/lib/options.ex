defmodule ExESDB.Options do
  @moduledoc """
    This module contains the options helper functions for ExESDB
    
    Modified to support umbrella configuration patterns where configurations
    are stored under individual app names instead of the global :ex_esdb key.
  """
  alias ExESDB.EnVars, as: EnVars

  @data_dir EnVars.data_dir()
  @store_id EnVars.store_id()
  @timeout EnVars.timeout()
  @db_type EnVars.db_type()
  @pub_sub EnVars.pub_sub()
  @writer_idle_ms EnVars.writer_idle_ms()
  @reader_idle_ms EnVars.reader_idle_ms()
  @store_description EnVars.store_description()
  @store_tags EnVars.store_tags()
  @persistence_interval EnVars.persistence_interval()
  @persistence_enabled EnVars.persistence_enabled()

  def sys_env(key), do: System.get_env(key)

  # Support for umbrella configuration patterns
  def app_env(otp_app) when is_atom(otp_app) do
    config = Application.get_env(otp_app, :ex_esdb, [])
    enhanced_config = Keyword.put(config, :otp_app, otp_app)
    enhanced_config
  end

  # Support for umbrella configuration patterns with defaults
  def app_env(otp_app, key, default) when is_atom(otp_app) and is_atom(key) do
    Keyword.get(app_env(otp_app), key, default)
  end

  def topologies, do: Application.get_env(:libcluster, :topologies)

  # Configuration context support for umbrella apps
  def set_context(otp_app) when is_atom(otp_app) do
    Process.put(:ex_esdb_otp_app, otp_app)
  end

  def get_context do
    Process.get(:ex_esdb_otp_app, :ex_esdb)
  end

  # Enhanced version that tries harder to find the context
  def get_context_or_discover do
    case get_context() do
      :ex_esdb ->
        # Try to discover from application environment or loaded apps
        discover_current_app() || :ex_esdb
      context -> 
        context
    end
  end

  # Helper to discover current app when context is not set
  # The simple approach: find which application has ExESDB configuration
  defp discover_current_app do
    # First try loaded applications
    loaded_app = Application.loaded_applications()
    |> Enum.find_value(fn {app, _desc, _vsn} ->
      case Application.get_env(app, :ex_esdb) do
        nil -> nil
        _config -> app
      end
    end)
    
    if loaded_app do
      loaded_app
    else
      # If no loaded app has config, use the built-in Erlang application environment mechanism
      # This is the "out-of-the-box" approach: check all apps that have our key set
      :application.info()
      |> Keyword.get(:loaded, [])
      |> Enum.find_value(fn app ->
        case :application.get_env(app, :ex_esdb) do
          {:ok, _config} -> app
          :undefined -> nil
        end
      end)
    end
  end

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

  # Umbrella-aware versions of configuration functions
  def data_dir(otp_app) when is_atom(otp_app) do
    case sys_env(@data_dir) do
      nil -> app_env(otp_app, :data_dir, "/data")
      data_dir -> data_dir
    end
  end

  def data_dir do
    context = get_context_or_discover()
    
    if context != :ex_esdb do
      data_dir(context)
    else
      case sys_env(@data_dir) do
        nil -> app_env(:ex_esdb, :data_dir, "/data")
        data_dir -> data_dir
      end
    end
  end

  def store_id(otp_app) when is_atom(otp_app) do
    case sys_env(@store_id) do
      nil -> app_env(otp_app, :store_id, :undefined)
      store_id -> to_unique_atom(store_id)
    end
  end

  def store_id do
    context = get_context_or_discover()

    if context != :ex_esdb do
      store_id(context)
    else
      case sys_env(@store_id) do
        nil -> app_env(:ex_esdb, :store_id, :undefined)
        store_id -> to_unique_atom(store_id)
      end
    end
  end

  def timeout(otp_app) when is_atom(otp_app) do
    case sys_env(@timeout) do
      nil -> app_env(otp_app, :timeout, 10_000)
      timeout -> String.to_integer(timeout)
    end
  end

  def timeout do
    context = get_context_or_discover()

    if context != :ex_esdb do
      timeout(context)
    else
      case sys_env(@timeout) do
        nil -> app_env(:ex_esdb, :timeout, 10_000)
        timeout -> String.to_integer(timeout)
      end
    end
  end

  def db_type(:ex_esdb), do: db_type()

  def db_type(otp_app) when is_atom(otp_app) do
    case sys_env(@db_type) do
      nil -> app_env(otp_app, :db_type, :single)
      db_type -> String.to_atom(db_type)
    end
  end

  def db_type do
    context = get_context_or_discover()

    if context != :ex_esdb do
      db_type(context)
    else
      case sys_env(@db_type) do
        nil -> app_env(:ex_esdb, :db_type, :single)
        db_type -> String.to_atom(db_type)
      end
    end
  end

  def pub_sub(otp_app) when is_atom(otp_app) do
    case sys_env(@pub_sub) do
      nil -> app_env(otp_app, :pub_sub, :ex_esdb_pubsub)
      pub_sub -> to_unique_atom(pub_sub)
    end
  end

  def pub_sub do
    context = get_context_or_discover()

    if context != :ex_esdb do
      pub_sub(context)
    else
      case sys_env(@pub_sub) do
        nil -> app_env(:ex_esdb, :pub_sub, :ex_esdb_pubsub)
        pub_sub -> to_unique_atom(pub_sub)
      end
    end
  end

  def reader_idle_ms(otp_app) when is_atom(otp_app) do
    case sys_env(@reader_idle_ms) do
      nil -> app_env(otp_app, :reader_idle_ms, 10_000)
      reader_idle_ms -> String.to_integer(reader_idle_ms)
    end
  end

  def reader_idle_ms do
    context = get_context_or_discover()

    if context != :ex_esdb do
      reader_idle_ms(context)
    else
      case sys_env(@reader_idle_ms) do
        nil -> app_env(:ex_esdb, :reader_idle_ms, 10_000)
        reader_idle_ms -> String.to_integer(reader_idle_ms)
      end
    end
  end

  def writer_idle_ms(otp_app) when is_atom(otp_app) do
    case sys_env(@writer_idle_ms) do
      nil -> app_env(otp_app, :writer_idle_ms, 10_000)
      writer_idle_ms -> String.to_integer(writer_idle_ms)
    end
  end

  def writer_idle_ms do
    context = get_context_or_discover()

    if context != :ex_esdb do
      writer_idle_ms(context)
    else
      case sys_env(@writer_idle_ms) do
        nil -> app_env(:ex_esdb, :writer_idle_ms, 10_000)
        writer_idle_ms -> String.to_integer(writer_idle_ms)
      end
    end
  end

  def store_description(otp_app) when is_atom(otp_app) do
    case sys_env(@store_description) do
      nil -> app_env(otp_app, :store_description, "undefined!")
      store_description -> store_description
    end
  end

  def store_description do
    context = get_context_or_discover()

    if context != :ex_esdb do
      store_description(context)
    else
      case sys_env(@store_description) do
        nil -> app_env(:ex_esdb, :store_description, "undefined!")
        store_description -> store_description
      end
    end
  end

  def store_tags(otp_app) when is_atom(otp_app) do
    case sys_env(@store_tags) do
      nil ->
        app_env(otp_app, :store_tags, [])

      tags_string ->
        tags_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  def store_tags do
    context = get_context_or_discover()

    if context != :ex_esdb do
      store_tags(context)
    else
      case sys_env(@store_tags) do
        nil ->
          app_env(:ex_esdb, :store_tags, [])

        tags_string ->
          tags_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
      end
    end
  end

  def persistence_interval(otp_app) when is_atom(otp_app) do
    case sys_env(@persistence_interval) do
      nil -> app_env(otp_app, :persistence_interval, 5_000)
      interval -> String.to_integer(interval)
    end
  end

  def persistence_interval do
    context = get_context_or_discover()

    if context != :ex_esdb do
      persistence_interval(context)
    else
      case sys_env(@persistence_interval) do
        nil -> app_env(:ex_esdb, :persistence_interval, 5_000)
        interval -> String.to_integer(interval)
      end
    end
  end

  def persistence_enabled(otp_app) when is_atom(otp_app) do
    case sys_env(@persistence_enabled) do
      nil -> app_env(otp_app, :persistence_enabled, true)
      enabled -> String.to_atom(enabled)
    end
  end

  def persistence_enabled do
    context = get_context_or_discover()

    if context != :ex_esdb do
      persistence_enabled(context)
    else
      case sys_env(@persistence_enabled) do
        nil -> app_env(:ex_esdb, :persistence_enabled, true)
        enabled -> String.to_atom(enabled)
      end
    end
  end

  defp to_unique_atom(candidate) do
    try do
      String.to_existing_atom(candidate)
    rescue
      _ -> String.to_atom(candidate)
    end
  end
end
