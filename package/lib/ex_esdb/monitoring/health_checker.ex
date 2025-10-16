defmodule ExESDB.Monitoring.HealthChecker do
  @moduledoc """
  Performs comprehensive health checks on the ExESDB system.
  
  Monitors system processes, configuration validity, resource usage,
  and overall system health to detect potential issues.
  """
  
  use GenServer
  
  alias ExESDB.PubSubIntegration
  
  # API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def perform_health_check(store_id \\ nil) do
    GenServer.call(__MODULE__, {:health_check, store_id})
  end
  
  def check_system_processes(store_id \\ nil) do
    GenServer.call(__MODULE__, {:check_system_processes, store_id})
  end
  
  def check_resource_usage() do
    GenServer.call(__MODULE__, :check_resource_usage)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:health_check, store_id}, _from, state) do
    store_id = store_id || :default_store
    
    checks = [
      {"System Processes", fn -> check_processes(store_id) end},
      {"Configuration", fn -> check_configuration(store_id) end},
      {"Resource Usage", fn -> check_resources() end},
      {"Supervision Tree", fn -> check_supervision(store_id) end},
      {"Subscription Health", fn -> check_subscription_health(store_id) end}
    ]
    
    results = perform_checks(checks)
    health_status = determine_health_status(results)
    
    # Broadcast health check results
    health_summary = %{
      store_id: store_id,
      status: health_status,
      check_count: length(results),
      timestamp: DateTime.utc_now()
    }
    
    case health_status do
      :healthy ->
        PubSubIntegration.broadcast_health_update(:health_checker, :healthy, health_summary)
      :degraded ->
        PubSubIntegration.broadcast_health_update(:health_checker, :degraded, health_summary)
        PubSubIntegration.broadcast_alert(:health_degraded, :warning, "System health degraded", health_summary)
      :unhealthy ->
        PubSubIntegration.broadcast_health_update(:health_checker, :unhealthy, health_summary)
        PubSubIntegration.broadcast_alert(:health_critical, :critical, "System health critical", health_summary)
    end
    
    {:reply, {:ok, %{status: health_status, results: results}}, state}
  end
  
  @impl true
  def handle_call({:check_system_processes, store_id}, _from, state) do
    result = check_processes(store_id)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:check_resource_usage, _from, state) do
    result = check_resources()
    {:reply, result, state}
  end
  
  # Private functions
  
  defp perform_checks(checks) do
    Enum.map(checks, fn {name, check_fn} ->
      case safe_check_execution(check_fn) do
        {:ok, result} -> {name, result}
        {:error, reason} -> {name, {:error, reason}}
      end
    end)
  end
  
  defp determine_health_status(results) do
    errors = Enum.count(results, fn {_, result} -> match?({:error, _}, result) end)
    warnings = Enum.count(results, fn {_, result} -> match?({:warning, _}, result) end)
    
    cond do
      errors > 0 -> :unhealthy
      warnings > 0 -> :degraded
      true -> :healthy
    end
  end
  
  defp check_processes(store_id) do
    system_name = ExESDB.System.system_name(store_id)
    
    result = case Process.whereis(system_name) do
      nil -> {:error, "System process not found"}
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok
        else
          {:error, "System process is dead"}
        end
    end
    
    # Broadcast specific process health status
    case result do
      :ok ->
        PubSubIntegration.broadcast_health_update(
          :system_process, 
          :healthy, 
          %{store_id: store_id, process: system_name}
        )
      {:error, reason} ->
        PubSubIntegration.broadcast_alert(
          :process_failure, 
          :critical, 
          "System process check failed: #{reason}", 
          %{store_id: store_id, process: system_name}
        )
    end
    
    result
  end
  
  defp check_configuration(_store_id) do
    # Basic configuration check - using defensive programming instead of try..rescue
    case validate_basic_configuration() do
      :ok -> :ok
      {:error, reason} -> {:error, "Configuration validation failed: #{reason}"}
    end
  end
  
  defp check_resources() do
    {memory_total, memory_used, _} = :memsup.get_memory_data()
    memory_utilization = (memory_used / memory_total) * 100
    
    process_count = length(Process.list())
    process_limit = :erlang.system_info(:process_limit)
    process_utilization = (process_count / process_limit) * 100
    
    resource_metrics = %{
      memory_utilization: Float.round(memory_utilization, 2),
      process_utilization: Float.round(process_utilization, 2),
      memory_used: memory_used,
      memory_total: memory_total,
      process_count: process_count,
      process_limit: process_limit
    }
    
    # Broadcast resource metrics
    PubSubIntegration.broadcast_metrics(:system_resources, resource_metrics)
    
    result = cond do
      memory_utilization > 90 or process_utilization > 90 ->
        {:error, "Critical resource usage"}
      memory_utilization > 75 or process_utilization > 75 ->
        {:warning, "High resource usage"}
      true ->
        :ok
    end
    
    # Broadcast resource alerts if needed
    case result do
      {:error, message} ->
        PubSubIntegration.broadcast_alert(
          :resource_critical, 
          :critical, 
          message, 
          resource_metrics
        )
      {:warning, message} ->
        PubSubIntegration.broadcast_alert(
          :resource_warning, 
          :warning, 
          message, 
          resource_metrics
        )
      :ok ->
        :ok
    end
    
    result
  end
  
  defp check_supervision(store_id) do
    system_name = ExESDB.System.system_name(store_id)
    
    case Process.whereis(system_name) do
      nil -> {:error, "System supervisor not found"}
      pid ->
        case safe_supervisor_inspection(pid) do
          {:ok, children} ->
            alive_children = Enum.count(children, fn {_, child_pid, _, _} ->
              child_pid != :undefined and Process.alive?(child_pid)
            end)
            
            if alive_children == length(children) do
              :ok
            else
              {:warning, "#{alive_children}/#{length(children)} children alive"}
            end
          {:error, _reason} ->
            {:error, "Unable to inspect supervision tree"}
        end
    end
  end
  
  defp check_subscription_health(store_id) do
    case safe_subscription_health_check(store_id) do
      {:ok, summary} ->
        total = summary.total_subscriptions
        failed = summary.failed
        degraded = summary.degraded
        
        cond do
          total == 0 ->
            :ok  # No subscriptions is not an error
          failed > 0 ->
            {:error, "#{failed}/#{total} subscriptions failed"}
          degraded > 0 ->
            {:warning, "#{degraded}/#{total} subscriptions degraded"}
          true ->
            :ok
        end
      {:error, reason} ->
        {:warning, "Unable to check subscription health: #{inspect(reason)}"}
    end
  end

  ## Helper Functions for Safe External Calls

  defp safe_check_execution(check_fn) do
    case check_fn.() do
      result -> {:ok, result}
    end
  catch
    :error, reason -> {:error, "Error: #{inspect(reason)}"}
    :exit, reason -> {:error, "Exit: #{inspect(reason)}"}
    reason -> {:error, "Throw: #{inspect(reason)}"}
  end

  defp validate_basic_configuration do
    # This is a placeholder for actual configuration validation
    # In a real implementation, you'd check various configuration aspects
    :ok
  end

  defp safe_supervisor_inspection(pid) do
    case Supervisor.which_children(pid) do
      children when is_list(children) -> {:ok, children}
      other -> {:error, {:unexpected_result, other}}
    end
  catch
    :error, reason -> {:error, {:caught_error, reason}}
    :exit, reason -> {:error, {:caught_exit, reason}}
    reason -> {:error, {:caught_throw, reason}}
  end

  defp safe_subscription_health_check(store_id) do
    case ExESDB.SubscriptionHealthTracker.get_store_health_summary(store_id) do
      {:ok, summary} -> {:ok, summary}
      {:error, reason} -> {:error, reason}
    end
  catch
    :error, reason -> {:error, {:caught_error, reason}}
    :exit, reason -> {:error, {:caught_exit, reason}}
    reason -> {:error, {:caught_throw, reason}}
  end
end
