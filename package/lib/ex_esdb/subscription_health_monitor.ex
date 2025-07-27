defmodule ExESDB.SubscriptionHealthMonitor do
  @moduledoc """
  Monitors the health of subscriptions and their associated emitter pools.
  
  This module provides comprehensive health monitoring for the subscription system:
  - Detects stale subscriptions (subscriber process is dead)
  - Identifies orphaned emitter pools (pools without corresponding subscriptions)
  - Finds missing emitter pools (subscriptions without pools on leader nodes)
  - Automatically triggers cleanup and recovery actions
  - Provides detailed health reports for observability
  
  The monitor runs periodic health checks and can be triggered manually for
  immediate diagnostics.
  """
  
  use GenServer
  require Logger
  
  alias ExESDB.Emitters
  alias ExESDB.EmitterPool
  alias ExESDB.StoreCluster
  alias ExESDB.StoreNaming
  alias ExESDB.Topics
  
  @default_check_interval 60_000  # 1 minute
  @default_cleanup_enabled true
  @default_max_cleanup_attempts 3
  @default_cleanup_retry_delay 5_000  # 5 seconds
  
  defstruct [
    :store_id,
    :check_interval,
    :cleanup_enabled,
    :last_check_time,
    :last_health_report,
    :cleanup_attempts,
    :max_cleanup_attempts,
    :cleanup_retry_delay,
    :timer_ref
  ]
  
  # API Functions
  
  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end
  
  @doc """
  Perform an immediate health check and return the results.
  """
  def health_check(store_id) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, :health_check, 30_000)
  end
  
  @doc """
  Get the last health report without performing a new check.
  """
  def last_health_report(store_id) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, :get_last_health_report)
  end
  
  @doc """
  Enable or disable automatic cleanup of detected issues.
  """
  def set_cleanup_enabled(store_id, enabled) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, {:set_cleanup_enabled, enabled})
  end
  
  @doc """
  Force cleanup of a specific subscription or emitter pool.
  """
  def force_cleanup(store_id, cleanup_action) do
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    GenServer.call(name, {:force_cleanup, cleanup_action})
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    check_interval = Keyword.get(opts, :health_check_interval, @default_check_interval)
    cleanup_enabled = Keyword.get(opts, :cleanup_enabled, @default_cleanup_enabled)
    max_cleanup_attempts = Keyword.get(opts, :max_cleanup_attempts, @default_max_cleanup_attempts)
    cleanup_retry_delay = Keyword.get(opts, :cleanup_retry_delay, @default_cleanup_retry_delay)
    
    state = %__MODULE__{
      store_id: store_id,
      check_interval: check_interval,
      cleanup_enabled: cleanup_enabled,
      max_cleanup_attempts: max_cleanup_attempts,
      cleanup_retry_delay: cleanup_retry_delay,
      cleanup_attempts: %{},
      last_health_report: nil
    }
    
    # Schedule initial health check
    timer_ref = Process.send_after(self(), :periodic_health_check, check_interval)
    state = %{state | timer_ref: timer_ref}
    
    Logger.info("SubscriptionHealthMonitor started for store #{store_id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    {health_report, updated_state} = perform_health_check(state)
    {:reply, health_report, updated_state}
  end
  
  @impl true
  def handle_call(:get_last_health_report, _from, state) do
    {:reply, state.last_health_report, state}
  end
  
  @impl true
  def handle_call({:set_cleanup_enabled, enabled}, _from, state) do
    updated_state = %{state | cleanup_enabled: enabled}
    Logger.info("SubscriptionHealthMonitor cleanup #{if enabled, do: "enabled", else: "disabled"} for store #{state.store_id}")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:force_cleanup, cleanup_action}, _from, state) do
    result = execute_cleanup_action(cleanup_action, state)
    {:reply, result, state}
  end
  
  @impl true
  def handle_info(:periodic_health_check, state) do
    {_health_report, updated_state} = perform_health_check(state)
    
    # Schedule next health check
    timer_ref = Process.send_after(self(), :periodic_health_check, state.check_interval)
    final_state = %{updated_state | timer_ref: timer_ref}
    
    {:noreply, final_state}
  end
  
  @impl true
  def handle_info({:retry_cleanup, cleanup_action}, state) do
    execute_cleanup_action(cleanup_action, state)
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end
    
    Logger.info("SubscriptionHealthMonitor terminating for store #{state.store_id}: #{inspect(reason)}")
    :ok
  end
  
  # Private Functions
  
  defp perform_health_check(state) do
    Logger.debug("Performing health check for store #{state.store_id}")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Gather all health data
    subscriptions = get_all_subscriptions(state.store_id)
    running_emitter_pools = get_running_emitter_pools(state.store_id)
    is_leader = StoreCluster.leader?(state.store_id)
    
    # Analyze health issues
    stale_subscriptions = find_stale_subscriptions(subscriptions)
    orphaned_pools = find_orphaned_emitter_pools(subscriptions, running_emitter_pools)
    missing_pools = if is_leader, do: find_missing_emitter_pools(subscriptions, running_emitter_pools), else: []
    
    # Create health report
    end_time = System.monotonic_time(:millisecond)
    check_duration = end_time - start_time
    
    health_report = %{
      timestamp: DateTime.utc_now(),
      store_id: state.store_id,
      is_leader: is_leader,
      check_duration_ms: check_duration,
      total_subscriptions: length(subscriptions),
      total_emitter_pools: length(running_emitter_pools),
      issues: %{
        stale_subscriptions: stale_subscriptions,
        orphaned_pools: orphaned_pools,
        missing_pools: missing_pools
      },
      summary: %{
        stale_subscription_count: length(stale_subscriptions),
        orphaned_pool_count: length(orphaned_pools),
        missing_pool_count: length(missing_pools),
        total_issues: length(stale_subscriptions) + length(orphaned_pools) + length(missing_pools)
      }
    }
    
    # Log health status
    log_health_report(health_report)
    
    # Perform cleanup if enabled
    updated_state = if state.cleanup_enabled do
      perform_automatic_cleanup(health_report, state)
    else
      state
    end
    
    final_state = %{updated_state | 
      last_check_time: DateTime.utc_now(),
      last_health_report: health_report
    }
    
    {health_report, final_state}
  end
  
  defp get_all_subscriptions(store_id) do
    try do
      case :khepri.get_many(store_id, [:subscriptions, :_]) do
        {:ok, subscription_map} ->
          subscription_map
          |> Enum.map(fn {_path, subscription} -> subscription end)
          |> Enum.filter(&is_map/1)
        
        {:error, reason} ->
          Logger.warning("Failed to get subscriptions for health check: #{inspect(reason)}")
          []
      end
    rescue
      error ->
        Logger.error("Error getting subscriptions for health check: #{inspect(error)}")
        []
    end
  end
  
  defp get_running_emitter_pools(store_id) do
    try do
      # Get all processes registered under the EmitterPools partition supervisor
      partition_name = StoreNaming.partition_name(ExESDB.EmitterPools, store_id)
      
      case Process.whereis(partition_name) do
        nil -> []
        partition_pid ->
          # Get all dynamic supervisors under the partition supervisor
          PartitionSupervisor.which_children(partition_pid)
          |> Enum.flat_map(fn {_partition, supervisor_pid} ->
            if supervisor_pid != :undefined and Process.alive?(supervisor_pid) do
              try do
                DynamicSupervisor.which_children(supervisor_pid)
                |> Enum.map(fn {_id, pool_pid, _type, _modules} -> pool_pid end)
                |> Enum.filter(&Process.alive?/1)
              rescue
                _ -> []
              end
            else
              []
            end
          end)
      end
    rescue
      error ->
        Logger.error("Error getting running emitter pools: #{inspect(error)}")
        []
    end
  end
  
  defp find_stale_subscriptions(subscriptions) do
    Enum.filter(subscriptions, fn subscription ->
      case Map.get(subscription, :subscriber) do
        nil -> false
        pid when is_pid(pid) -> not Process.alive?(pid)
        _ -> false
      end
    end)
  end
  
  defp find_orphaned_emitter_pools(subscriptions, running_pools) do
    # Create a set of expected pool names based on subscriptions
    expected_pool_names = 
      subscriptions
      |> Enum.map(&subscription_to_pool_name/1)
      |> MapSet.new()
    
    # Find pools that don't have corresponding subscriptions
    Enum.filter(running_pools, fn pool_pid ->
      try do
        pool_name = get_pool_name_from_pid(pool_pid)
        pool_name != nil and not MapSet.member?(expected_pool_names, pool_name)
      rescue
        _ -> true  # If we can't determine the name, consider it orphaned
      end
    end)
  end
  
  defp find_missing_emitter_pools(subscriptions, running_pools) do
    # Create a set of running pool names
    running_pool_names = 
      running_pools
      |> Enum.map(&get_pool_name_from_pid/1)
      |> Enum.filter(& &1 != nil)
      |> MapSet.new()
    
    # Find subscriptions that should have pools but don't
    Enum.filter(subscriptions, fn subscription ->
      expected_pool_name = subscription_to_pool_name(subscription)
      expected_pool_name != nil and not MapSet.member?(running_pool_names, expected_pool_name)
    end)
  end
  
  defp subscription_to_pool_name(subscription) do
    try do
      %{type: type, subscription_name: name, selector: selector} = subscription
      sub_topic = Topics.sub_topic(type, name, selector)
      # Extract store_id from the subscription or use a default - this might need adjustment
      # based on how subscriptions store the store_id
      store_id = Map.get(subscription, :store_id, :default_store)
      EmitterPool.name(store_id, sub_topic)
    rescue
      _ -> nil
    end
  end
  
  defp get_pool_name_from_pid(pool_pid) do
    try do
      case Process.info(pool_pid, :registered_name) do
        {:registered_name, name} -> name
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end
  
  defp log_health_report(health_report) do
    %{summary: summary, store_id: store_id, is_leader: is_leader, total_subscriptions: total_subscriptions, total_emitter_pools: total_emitter_pools} = health_report
    
    if summary.total_issues == 0 do
      Logger.debug("SubscriptionHealthMonitor: Store #{store_id} healthy (#{total_subscriptions} subscriptions, #{total_emitter_pools} pools)")
    else
      Logger.warning("SubscriptionHealthMonitor: Store #{store_id} has #{summary.total_issues} issues - " <>
        "Stale: #{summary.stale_subscription_count}, Orphaned: #{summary.orphaned_pool_count}, Missing: #{summary.missing_pool_count} " <>
        "(Leader: #{is_leader})")
    end
  end
  
  defp perform_automatic_cleanup(health_report, state) do
    %{issues: issues} = health_report
    
    cleanup_actions = []
    
    # Add cleanup actions for stale subscriptions
    cleanup_actions = cleanup_actions ++ 
      Enum.map(issues.stale_subscriptions, fn subscription ->
        {:remove_stale_subscription, subscription}
      end)
    
    # Add cleanup actions for orphaned pools (only if leader)
    cleanup_actions = if health_report.is_leader do
      cleanup_actions ++ 
        Enum.map(issues.orphaned_pools, fn pool_pid ->
          {:stop_orphaned_pool, pool_pid}
        end)
    else
      cleanup_actions
    end
    
    # Add cleanup actions for missing pools (only if leader)
    cleanup_actions = if health_report.is_leader do
      cleanup_actions ++ 
        Enum.map(issues.missing_pools, fn subscription ->
          {:start_missing_pool, subscription}
        end)
    else
      cleanup_actions
    end
    
    # Execute cleanup actions
    Enum.each(cleanup_actions, fn action ->
      execute_cleanup_action(action, state)
    end)
    
    state
  end
  
  defp execute_cleanup_action({:remove_stale_subscription, subscription}, state) do
    try do
      Logger.info("Removing stale subscription: #{inspect(subscription.subscription_name)}")
      :subscriptions_store.delete_subscription(state.store_id, subscription)
      :ok
    rescue
      error ->
        Logger.error("Failed to remove stale subscription: #{inspect(error)}")
        schedule_cleanup_retry({:remove_stale_subscription, subscription}, state)
        {:error, error}
    end
  end
  
  defp execute_cleanup_action({:stop_orphaned_pool, pool_pid}, state) do
    try do
      pool_name = get_pool_name_from_pid(pool_pid)
      Logger.info("Stopping orphaned emitter pool: #{inspect(pool_name)}")
      
      if pool_pid && Process.alive?(pool_pid) do
        GenServer.stop(pool_pid, :normal, 5000)
      end
      :ok
    rescue
      error ->
        Logger.error("Failed to stop orphaned pool: #{inspect(error)}")
        schedule_cleanup_retry({:stop_orphaned_pool, pool_pid}, state)
        {:error, error}
    end
  end
  
  defp execute_cleanup_action({:start_missing_pool, subscription}, state) do
    try do
      Logger.info("Starting missing emitter pool for subscription: #{inspect(subscription.subscription_name)}")
      
      case Emitters.start_emitter_pool(state.store_id, subscription) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok  # Pool was started by another process
        {:error, reason} -> 
          Logger.warning("Failed to start missing emitter pool: #{inspect(reason)}")
          schedule_cleanup_retry({:start_missing_pool, subscription}, state)
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error starting missing emitter pool: #{inspect(error)}")
        schedule_cleanup_retry({:start_missing_pool, subscription}, state)
        {:error, error}
    end
  end
  
  defp schedule_cleanup_retry(cleanup_action, state) do
    action_key = elem(cleanup_action, 0)
    current_attempts = Map.get(state.cleanup_attempts, action_key, 0)
    
    if current_attempts < state.max_cleanup_attempts do
      Logger.info("Scheduling cleanup retry for #{inspect(action_key)} (attempt #{current_attempts + 1}/#{state.max_cleanup_attempts})")
      Process.send_after(self(), {:retry_cleanup, cleanup_action}, state.cleanup_retry_delay)
      
      # Update attempt count
      updated_attempts = Map.put(state.cleanup_attempts, action_key, current_attempts + 1)
      %{state | cleanup_attempts: updated_attempts}
    else
      Logger.error("Max cleanup attempts reached for #{inspect(action_key)}, giving up")
      state
    end
  end
end
