#!/usr/bin/env elixir

# Test script showing different ways an OTP app can discover its own name

defmodule AppDiscoveryTest do
  @moduledoc """
  Demonstrates various methods for an OTP application to discover its own name.
  """

  def test_all_methods do
    IO.puts("=== OTP Application Name Discovery Methods ===\n")
    
    # Method 1: Using Application.get_application/1 with self()
    test_get_application_self()
    
    # Method 2: Using Application.get_application/1 with module
    test_get_application_module()
    
    # Method 3: Using Application.loaded_applications/0
    test_loaded_applications()
    
    # Method 4: Using Application.spec/2
    test_application_spec()
    
    # Method 5: Using Mix.Project (compile-time)
    test_mix_project()
    
    # Method 6: Environment-based discovery
    test_environment_discovery()
  end
  
  defp test_get_application_self do
    IO.puts("1. Application.get_application/1 only works with modules, not PIDs")
    IO.puts("   → Application.get_application/1 requires atom (module), not PID")
    IO.puts("   → Use Process.info(self(), :dictionary) to check process context instead")
    IO.puts("")
  end
  
  defp test_get_application_module do
    IO.puts("2. Application.get_application(__MODULE__):")
    case Application.get_application(__MODULE__) do
      nil -> IO.puts("   → nil (module not part of any application)")
      app -> IO.puts("   → #{inspect(app)}")
    end
    IO.puts("")
  end
  
  defp test_loaded_applications do
    IO.puts("3. Application.loaded_applications() (find current context):")
    apps = Application.loaded_applications()
    current_app = find_current_app(apps)
    IO.puts("   → Found #{length(apps)} loaded applications")
    IO.puts("   → Current app heuristic: #{inspect(current_app)}")
    IO.puts("")
  end
  
  defp test_application_spec do
    IO.puts("4. Application.spec(:ex_esdb, :description):")
    case Application.spec(:ex_esdb, :description) do
      nil -> IO.puts("   → nil (app not loaded)")
      desc -> IO.puts("   → #{desc}")
    end
    IO.puts("")
  end
  
  defp test_mix_project do
    IO.puts("5. Mix.Project.config() (compile-time discovery):")
    try do
      config = Mix.Project.config()
      app_name = Keyword.get(config, :app)
      IO.puts("   → #{inspect(app_name)}")
    rescue
      _e -> IO.puts("   → Mix not available (runtime context)")
    catch
      :exit, _reason -> IO.puts("   → Mix ProjectStack not available (runtime context)")
    end
    IO.puts("")
  end
  
  defp test_environment_discovery do
    IO.puts("6. Environment-based discovery:")
    
    # Check if we're in IEx
    iex_running = Code.ensure_loaded?(IEx) && Process.whereis(IEx.Server)
    IO.puts("   → IEx running: #{iex_running}")
    
    # Check application environment for hints
    otp_app_env = Application.get_env(:ex_esdb, :otp_app)
    IO.puts("   → :ex_esdb :otp_app env: #{inspect(otp_app_env)}")
    
    IO.puts("")
  end
  
  # Helper to find the "current" application based on heuristics
  defp find_current_app(loaded_apps) do
    # Look for non-standard Erlang/Elixir apps (heuristic for user apps)
    user_apps = Enum.filter(loaded_apps, fn {app, _desc, _vsn} ->
      app_str = Atom.to_string(app)
      not (String.starts_with?(app_str, "kernel") or
           String.starts_with?(app_str, "stdlib") or
           String.starts_with?(app_str, "sasl") or
           String.starts_with?(app_str, "crypto") or
           app in [:logger, :runtime_tools, :ssl, :inets, :public_key])
    end)
    
    case user_apps do
      [{app, _desc, _vsn} | _] -> app
      [] -> :unknown
      multiple -> 
        IO.puts("   → Multiple user apps found: #{inspect(Enum.map(multiple, fn {app, _, _} -> app end))}")
        :multiple
    end
  end
end

# Additional helper functions that can be used in real applications
defmodule AppNameDiscovery do
  @moduledoc """
  Practical functions for OTP application name discovery.
  """
  
  @doc """
  Discovers the current application name using multiple strategies.
  
  Tries methods in order of reliability:
  1. Explicit process dictionary lookup
  2. Application.get_application/1 with calling process
  3. Mix.Project if available (compile-time)
  4. Environment variable fallback
  5. Default to :ex_esdb
  """
  def discover_app_name do
    Process.get(:otp_app) ||
    try_mix_project() ||
    System.get_env("OTP_APP") |> maybe_atom() ||
    try_loaded_applications() ||
    :ex_esdb
  end
  
  @doc """
  More robust discovery that tries multiple process contexts.
  """
  def discover_app_name_robust do
    # Try multiple discovery methods
    Process.get(:otp_app) ||
    discover_from_context() ||
    try_mix_project() ||
    try_loaded_applications()
  end
  
  @doc """
  Set the application context in process dictionary.
  This is the most reliable method for umbrella apps.
  """
  def set_app_context(otp_app) when is_atom(otp_app) do
    Process.put(:otp_app, otp_app)
  end
  
  @doc """
  Get application name from Mix project (compile-time only).
  """
  def get_mix_app_name do
    try_mix_project()
  end
  
  # Private helpers
  
  defp discover_from_context do
    # Try to find from supervisor tree or registered processes
    case Process.info(self(), :registered_name) do
      {_, []} -> try_loaded_applications()
      {_, name} -> extract_app_from_name(name)
    end
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
      app not in [:logger, :runtime_tools, :crypto]
    end)
    |> case do
      {app, _, _} -> app
      nil -> nil
    end
  end
  
  defp extract_app_from_name(name) when is_atom(name) do
    # Try to extract app name from registered process name
    name_str = Atom.to_string(name)
    if String.contains?(name_str, "_") do
      name_str |> String.split("_") |> List.first() |> String.to_atom()
    else
      nil
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
end

# Run the tests
AppDiscoveryTest.test_all_methods()

IO.puts("=== Practical Discovery Functions ===")
IO.puts("AppNameDiscovery.discover_app_name(): #{inspect(AppNameDiscovery.discover_app_name())}")
IO.puts("AppNameDiscovery.discover_app_name_robust(): #{inspect(AppNameDiscovery.discover_app_name_robust())}")
IO.puts("AppNameDiscovery.get_mix_app_name(): #{inspect(AppNameDiscovery.get_mix_app_name())}")
