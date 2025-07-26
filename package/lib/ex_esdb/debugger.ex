defmodule ExESDB.Debugger do
  @moduledoc """
  Comprehensive debugging and inspection API for ExESDB systems.
  
  This module provides REPL-friendly functions to investigate all aspects
  of an ExESDB Event Sourcing Database by delegating to specialized subsystems:
  
  - Process supervision tree inspection (Inspector)
  - Health and performance monitoring (Monitor)
  - Scenario testing and simulation (ScenarioManager)
  - Real-time observation (Observer)
  
  ## Usage in REPL
  
      iex> ExESDB.Debugger.overview()
      iex> ExESDB.Debugger.start_scenario(:high_load, intensity: :medium)
      iex> ExESDB.Debugger.observe(:system_metrics)
  """
  
  require Logger
  
  # ===================
  # System Overview
  # ===================
  
  @doc """
  Display a comprehensive overview of the ExESDB system.
  """
  def overview(store_id \\ nil) do
    IO.puts("\n🔍 ExESDB System Overview")
    IO.puts("=" <> String.duplicate("=", 40))
    
    # Get data from ProcessInspector
    case ExESDB.Inspection.ProcessInspector.list_processes() do
      processes when is_list(processes) ->
        alive_count = Enum.count(processes, fn {_, pid, _} -> Process.alive?(pid) end)
        total_memory = processes |> Enum.map(fn {_, _, info} -> info[:memory] || 0 end) |> Enum.sum()
        IO.puts("⚙️  Processes: #{alive_count}/#{length(processes)} alive")
        IO.puts("💾 Memory: #{format_memory(total_memory)}")
      _ ->
        IO.puts("❌ Unable to retrieve process information")
    end
    
    # Get health status from HealthChecker
    case ExESDB.Monitoring.HealthChecker.perform_health_check(store_id) do
      {:ok, %{status: status}} ->
        icon = case status do
          :healthy -> "✅"
          :degraded -> "⚠️"
          :unhealthy -> "❌"
        end
        IO.puts("#{icon} Health: #{status}")
      _ ->
        IO.puts("❌ Unable to retrieve health status")
    end
    
    IO.puts("\n💡 Use ExESDB.Debugger.help() for available commands")
  end
  
  @doc """
  Show help information for all available debugging commands.
  """
  def help do
    IO.puts("\n📚 ExESDB Debugger Help")
    IO.puts("=" <> String.duplicate("=", 50))
    
    sections = [
      {"🔍 System Inspection", [
        {"overview(store_id \\\\ nil)", "Complete system overview"},
        {"processes(store_id \\\\ nil)", "List all ExESDB processes"},
        {"supervision_tree(store_id \\\\ nil)", "Display supervision tree"},
        {"config(store_id \\\\ nil)", "Show configuration details"},
      ]},
      {"🏥 Health & Performance", [
        {"health(store_id \\\\ nil)", "Comprehensive health check"},
        {"performance(store_id \\\\ nil)", "Performance metrics"},
      ]},
      {"🎯 Scenario Testing", [
        {"start_scenario(name, opts \\\\ [])", "Start test scenario"},
        {"stop_scenario(scenario_id)", "Stop running scenario"},
        {"list_scenarios()", "List active scenarios"},
      ]},
      {"👁️ Real-time Observation", [
        {"observe(target, opts \\\\ [])", "Start real-time observation"},
        {"stop_observation(obs_id)", "Stop observation"},
        {"list_observations()", "List active observations"},
      ]},
      {"🔧 Advanced Tools", [
        {"trace(module, function, opts \\\\ [])", "Trace function calls"},
        {"benchmark(fun, opts \\\\ [])", "Benchmark a function"},
        {"observer()", "Start Erlang observer GUI"},
      ]}
    ]
    
    Enum.each(sections, fn {section_title, commands} ->
      IO.puts("\n#{section_title}")
      Enum.each(commands, fn {cmd, desc} ->
        IO.puts("  #{String.pad_trailing(cmd, 35)} - #{desc}")
      end)
    end)
    
    IO.puts("\n📖 Examples:")
    IO.puts("  ExESDB.Debugger.start_scenario(:high_load, intensity: :medium, duration: 30_000)")
    IO.puts("  ExESDB.Debugger.observe(:system_metrics, interval: 2000)")
    IO.puts("  ExESDB.Debugger.trace(ExESDB.StreamsWriter, :append_events)")
  end
  
  # ===================
  # Process Inspection
  # ===================
  
  @doc """
  List all ExESDB-related processes with formatted output.
  """
  def processes(_store_id \\ nil) do
    IO.puts("\n⚙️  ExESDB Processes")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Inspection.ProcessInspector.list_processes() do
      %{processes: processes, total_memory: memory, alive_count: alive} ->
        if Enum.empty?(processes) do
          IO.puts("📭 No ExESDB processes found")
        else
          Enum.each(processes, fn {type, procs} ->
            IO.puts("\n📦 #{type} (#{length(procs)} processes)")
            Enum.each(procs, fn proc ->
              status = if proc.alive, do: "✅", else: "❌"
              memory_str = format_memory(proc.memory)
              IO.puts("  #{status} #{String.pad_trailing(to_string(proc.name), 30)} #{inspect(proc.pid)} #{memory_str}")
            end)
          end)
          IO.puts("\n📊 Total: #{alive} alive, #{format_memory(memory)} memory")
        end
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  @doc """
  Display the supervision tree for ExESDB.
  """
  def supervision_tree(store_id \\ nil) do
    IO.puts("\n🌳 ExESDB Supervision Tree")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Inspection.TreeInspector.view_supervision_tree(store_id) do
      {:ok, tree} ->
        display_tree(tree, 0)
      {:error, reason} ->
        IO.puts("❌ #{reason}")
    end
  end
  
  @doc """
  Show detailed configuration for the store.
  """
  def config(store_id \\ nil) do
    IO.puts("\n⚙️  ExESDB Configuration")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Inspection.ConfigInspector.get_config(store_id) do
      {:ok, config} when is_map(config) ->
        Enum.each(config, fn {key, value} ->
          if key != :topologies do
            IO.puts("  #{String.pad_trailing(to_string(key), 20)} : #{inspect(value)}")
          end
        end)
        
        IO.puts("\n🔗 LibCluster Topologies:")
        case Map.get(config, :topologies) do
          nil -> IO.puts("  None configured")
          topologies when is_list(topologies) ->
            Enum.each(topologies, fn {name, topo_config} ->
              strategy = topo_config[:strategy] || "unknown"
              IO.puts("  #{name}: #{strategy}")
            end)
          _ -> IO.puts("  Invalid topology configuration")
        end
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  # ===================
  # Health & Performance
  # ===================
  
  @doc """
  Perform comprehensive health check.
  """
  def health(store_id \\ nil) do
    IO.puts("\n🏥 ExESDB Health Check")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Monitoring.HealthChecker.perform_health_check(store_id) do
      %{status: status, details: details} ->
        icon = if status == "Healthy", do: "✅", else: "⚠️"
        IO.puts("#{icon} Overall Status: #{status}")
        IO.puts("   Details: #{details}")
      {:error, reason} ->
        IO.puts("❌ Health check failed: #{inspect(reason)}")
    end
  end
  
  @doc """
  Show performance metrics.
  """
  def performance(_store_id \\ nil) do
    IO.puts("\n📈 Performance Metrics")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Observation.MetricsCollector.collect_system_metrics() do
      metrics when is_map(metrics) ->
        Enum.each(metrics, fn {key, value} ->
          IO.puts("  #{String.pad_trailing(to_string(key), 15)} : #{value}")
        end)
      {:error, reason} ->
        IO.puts("❌ Performance metrics unavailable: #{inspect(reason)}")
    end
  end
  
  # ===================
  # Scenario Management
  # ===================
  
  @doc """
  Start a test scenario.
  
  Available scenarios:
  - `:high_load` - Simulate high CPU/memory load
  - `:node_failure` - Simulate node failures
  - `:custom` - Load custom scenario from config
  
  ## Examples
  
      ExESDB.Debugger.start_scenario(:high_load, intensity: :medium, duration: 30_000)
      ExESDB.Debugger.start_scenario(:custom, config_path: "scenarios/custom.json")
  """
  def start_scenario(scenario_name, opts \\ []) do
    case ExESDB.Debugger.ScenarioManager.start_scenario(scenario_name, opts) do
      {:ok, scenario_id} ->
        IO.puts("✅ Started scenario #{inspect(scenario_name)} with ID: #{scenario_id}")
        {:ok, scenario_id}
      {:error, reason} ->
        IO.puts("❌ Failed to start scenario: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Stop a running scenario.
  """
  def stop_scenario(scenario_id) do
    case ExESDB.Debugger.ScenarioManager.stop_scenario(scenario_id) do
      :ok ->
        IO.puts("✅ Stopped scenario: #{scenario_id}")
        :ok
      {:error, reason} ->
        IO.puts("❌ Failed to stop scenario: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  List all running scenarios.
  """
  def list_scenarios do
    IO.puts("\n🎯 Active Scenarios")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Debugger.ScenarioManager.list_scenarios() do
      [] ->
        IO.puts("📭 No active scenarios")
      scenarios ->
        Enum.each(scenarios, fn scenario ->
          uptime = System.system_time(:millisecond) - scenario.started_at
          IO.puts("🎯 #{scenario.id}")
          IO.puts("   Name: #{scenario.name}")
          IO.puts("   Status: #{scenario.status}")
          IO.puts("   Uptime: #{format_uptime(uptime)}")
        end)
    end
  end
  
  # ===================
  # Real-time Observation
  # ===================
  
  @doc """
  Start real-time observation of system components.
  
  Available targets:
  - `:system_metrics` - Overall system metrics
  - `:process_metrics` - Specific process metrics (requires :target_process opt)
  - `:memory_usage` - Memory usage patterns
  
  ## Examples
  
      ExESDB.Debugger.observe(:system_metrics, interval: 1000)
      ExESDB.Debugger.observe(:process_metrics, target_process: :my_process, interval: 2000)
  """
  def observe(target, opts \\ []) do
    case ExESDB.Debugger.Observer.start_observation(target, opts) do
      {:ok, observation_id} ->
        IO.puts("👁️  Started observing #{inspect(target)} with ID: #{observation_id}")
        {:ok, observation_id}
      {:error, reason} ->
        IO.puts("❌ Failed to start observation: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Stop a running observation.
  """
  def stop_observation(observation_id) do
    case ExESDB.Debugger.Observer.stop_observation(observation_id) do
      :ok ->
        IO.puts("✅ Stopped observation: #{observation_id}")
        :ok
      {:error, reason} ->
        IO.puts("❌ Failed to stop observation: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  List all active observations.
  """
  def list_observations do
    IO.puts("\n👁️  Active Observations")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case ExESDB.Debugger.Observer.list_observations() do
      [] ->
        IO.puts("📭 No active observations")
      observations ->
        Enum.each(observations, fn obs ->
          uptime = System.system_time(:millisecond) - obs.started_at
          IO.puts("👁️  #{obs.id}")
          IO.puts("   Target: #{obs.target}")
          IO.puts("   Data Points: #{obs.data_points}")
          IO.puts("   Uptime: #{format_uptime(uptime)}")
        end)
    end
  end
  
  @doc """
  Get observation data for analysis.
  """
  def observation_data(observation_id) do
    case ExESDB.Debugger.Observer.get_observation_data(observation_id) do
      {:ok, data} -> data
      {:error, reason} -> 
        IO.puts("❌ Failed to get observation data: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # ===================
  # Advanced Tools
  # ===================
  
  @doc """
  Trace function calls for debugging.
  """
  def trace(module, function, opts \\ []) do
    duration = Keyword.get(opts, :duration, 5000)
    match_spec = Keyword.get(opts, :match_spec, :_)
    
    IO.puts("🔍 Tracing #{module}.#{function} for #{duration}ms...")
    
    # Start tracing
    :dbg.start()
    :dbg.tracer()
    :dbg.p(:all, :c)
    :dbg.tpl(module, function, match_spec)
    
    # Wait for specified duration
    Process.sleep(duration)
    
    # Stop tracing
    :dbg.stop()
    
    IO.puts("✅ Tracing complete")
  end
  
  @doc """
  Benchmark a function.
  """
  def benchmark(fun, opts \\ []) when is_function(fun) do
    times = Keyword.get(opts, :times, 1000)
    
    IO.puts("⏱️  Benchmarking function #{times} times...")
    
    {total_time, _} = :timer.tc(fn ->
      Enum.each(1..times, fn _ -> fun.() end)
    end)
    
    avg_time = total_time / times
    
    IO.puts("📊 Results:")
    IO.puts("  Total time: #{format_time(total_time)}")
    IO.puts("  Average time: #{format_time(avg_time)}")
    IO.puts("  Calls per second: #{Float.round(1_000_000 / avg_time, 2)}")
  end
  
  @doc """
  Start Erlang observer GUI.
  """
  def observer do
    IO.puts("🔍 Starting Erlang Observer...")
    :observer.start()
  end
  
  @doc """
  Show top processes by memory/CPU usage.
  """
  def top(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    sort_by = Keyword.get(opts, :sort_by, :memory)
    
    IO.puts("\n🔝 Top #{limit} Processes by #{sort_by}")
    IO.puts("=" <> String.duplicate("=", 60))
    
    processes = :recon.proc_count(sort_by, limit)
    
    IO.puts("#{String.pad_trailing("PID", 15)} #{String.pad_trailing("Name/Function", 30)} #{String.pad_trailing("Value", 15)}")
    IO.puts(String.duplicate("-", 60))
    
    Enum.each(processes, fn {pid, value, [name | _]} ->
      name_str = case name do
        atom when is_atom(atom) -> to_string(atom)
        other -> inspect(other)
      end
      
      formatted_value = case sort_by do
        :memory -> format_memory(value)
        _ -> to_string(value)
      end
      
      IO.puts("#{String.pad_trailing(inspect(pid), 15)} #{String.pad_trailing(name_str, 30)} #{formatted_value}")
    end)
  end
  
  # ===================
  # Helper Functions
  # ===================
  
  defp display_tree(tree, depth) do
    indent = String.duplicate("  ", depth)
    status = if tree.alive, do: "✅", else: "❌"
    
    IO.puts("#{indent}#{status} #{tree.name} (#{inspect(tree.pid)})")
    
    if tree.children do
      Enum.each(tree.children, fn child ->
        if child.children do
          display_tree(child, depth + 1)
        else
          child_indent = String.duplicate("  ", depth + 1)
          child_status = if child.alive, do: "✅", else: "❌"
          type_icon = case child.type do
            :supervisor -> "📁"
            :worker -> "⚙️"
            _ -> "❓"
          end
          IO.puts("#{child_indent}#{child_status} #{type_icon} #{child.id} (#{inspect(child.pid)})")
        end
      end)
    end
  end
  
  defp format_memory(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)}GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)}MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
      true -> "#{bytes}B"
    end
  end
  
  defp format_memory(_), do: "0B"
  
  defp format_time(microseconds) when is_number(microseconds) do
    cond do
      microseconds >= 1_000_000 -> "#{Float.round(microseconds / 1_000_000, 3)}s"
      microseconds >= 1_000 -> "#{Float.round(microseconds / 1_000, 3)}ms"
      true -> "#{Float.round(microseconds, 3)}μs"
    end
  end
  
  defp format_uptime(milliseconds) when is_number(milliseconds) do
    seconds = div(milliseconds, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)
    
    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end
end
