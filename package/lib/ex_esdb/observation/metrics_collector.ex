defmodule ExESDB.Observation.MetricsCollector do
  @moduledoc """
  Collects various system metrics for observation and analysis.
  
  Handles collection of CPU, memory, process count, and other
  system-wide metrics for real-time monitoring.
  """
  
  use GenServer
  
  # API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def collect_system_metrics() do
    GenServer.call(__MODULE__, :collect_system_metrics)
  end
  
  def collect_process_metrics(pid_or_name) do
    GenServer.call(__MODULE__, {:collect_process_metrics, pid_or_name})
  end
  
  def collect_memory_metrics() do
    GenServer.call(__MODULE__, :collect_memory_metrics)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
  
  @impl true
  def handle_call(:collect_system_metrics, _from, state) do
    metrics = gather_system_metrics()
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call({:collect_process_metrics, pid_or_name}, _from, state) do
    metrics = gather_process_metrics(pid_or_name)
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:collect_memory_metrics, _from, state) do
    metrics = gather_memory_metrics()
    {:reply, {:ok, metrics}, state}
  end
  
  # Private functions
  
  defp gather_system_metrics do
    {memory_total, memory_used, _} = :memsup.get_memory_data()
    cpu_cores = :erlang.system_info(:logical_processors_available)
    {uptime, _} = :erlang.statistics(:wall_clock)
    process_count = length(Process.list())
    
    %{
      memory_total: memory_total * 1024,  # Convert to bytes
      memory_used: memory_used * 1024,    # Convert to bytes
      memory_utilization: (memory_used / memory_total) * 100,
      cpu_cores: cpu_cores,
      uptime: uptime,
      process_count: process_count,
      timestamp: System.system_time(:millisecond)
    }
  end
  
  defp gather_process_metrics(pid_or_name) do
    pid = case pid_or_name do
      pid when is_pid(pid) -> pid
      name -> Process.whereis(name)
    end
    
    case pid do
      nil ->
        {:error, :process_not_found}
      
      pid when is_pid(pid) ->
        case Process.info(pid) do
          nil ->
            {:error, :process_dead}
          
          info ->
            {:ok, %{
              pid: pid,
              memory: info[:memory],
              message_queue_len: info[:message_queue_len],
              reductions: info[:reductions],
              status: info[:status],
              timestamp: System.system_time(:millisecond)
            }}
        end
    end
  end
  
  defp gather_memory_metrics do
    {memory_total, memory_used, _} = :memsup.get_memory_data()
    
    %{
      total: memory_total * 1024,
      used: memory_used * 1024,
      free: (memory_total - memory_used) * 1024,
      utilization: (memory_used / memory_total) * 100,
      timestamp: System.system_time(:millisecond)
    }
  end
end
