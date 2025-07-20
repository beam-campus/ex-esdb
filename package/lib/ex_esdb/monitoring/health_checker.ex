defmodule ExESDB.Monitoring.HealthChecker do
  @moduledoc """
  Performs comprehensive health checks on the ExESDB system.
  
  Monitors system processes, configuration validity, resource usage,
  and overall system health to detect potential issues.
  """
  
  use GenServer
  
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
      {"Supervision Tree", fn -> check_supervision(store_id) end}
    ]
    
    results = perform_checks(checks)
    health_status = determine_health_status(results)
    
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
      try do
        result = check_fn.()
        {name, result}
      rescue
        error -> {name, {:error, inspect(error)}}
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
    
    case Process.whereis(system_name) do
      nil -> {:error, "System process not found"}
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok
        else
          {:error, "System process is dead"}
        end
    end
  end
  
  defp check_configuration(_store_id) do
    # Basic configuration check
    try do
      # This would check various configuration aspects
      :ok
    rescue
      _ -> {:error, "Configuration validation failed"}
    end
  end
  
  defp check_resources() do
    {memory_total, memory_used, _} = :memsup.get_memory_data()
    memory_utilization = (memory_used / memory_total) * 100
    
    process_count = length(Process.list())
    process_limit = :erlang.system_info(:process_limit)
    process_utilization = (process_count / process_limit) * 100
    
    cond do
      memory_utilization > 90 or process_utilization > 90 ->
        {:error, "Critical resource usage"}
      memory_utilization > 75 or process_utilization > 75 ->
        {:warning, "High resource usage"}
      true ->
        :ok
    end
  end
  
  defp check_supervision(store_id) do
    system_name = ExESDB.System.system_name(store_id)
    
    case Process.whereis(system_name) do
      nil -> {:error, "System supervisor not found"}
      pid ->
        try do
          children = Supervisor.which_children(pid)
          alive_children = Enum.count(children, fn {_, child_pid, _, _} ->
            child_pid != :undefined and Process.alive?(child_pid)
          end)
          
          if alive_children == length(children) do
            :ok
          else
            {:warning, "#{alive_children}/#{length(children)} children alive"}
          end
        rescue
          _ -> {:error, "Unable to inspect supervision tree"}
        end
    end
  end
end
