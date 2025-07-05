defmodule ExESDB.NodeMonitor do
  @moduledoc """
  Provides fast failure detection and cluster health monitoring to handle hard node crashes.
  
  This module implements a multi-layer approach:
  1. Active health probing of cluster nodes
  2. Fast detection of unresponsive nodes
  3. Proactive cleanup of Swarm registrations
  4. Coordination with Khepri cluster management
  """
  use GenServer
  require Logger

  alias ExESDB.Themes

  @default_probe_interval 2_000  # 2 seconds
  @default_failure_threshold 3   # 3 consecutive failures
  @default_probe_timeout 1_000   # 1 second timeout per probe

  ## Public API

  @doc "Start the node monitor"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current cluster health status"
  def health_status do
    GenServer.call(__MODULE__, :health_status, 5_000)
  end

  @doc "Force probe a specific node"
  def probe_node(node) do
    GenServer.call(__MODULE__, {:probe_node, node}, 10_000)
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    probe_interval = Keyword.get(opts, :probe_interval, @default_probe_interval)
    failure_threshold = Keyword.get(opts, :failure_threshold, @default_failure_threshold)
    probe_timeout = Keyword.get(opts, :probe_timeout, @default_probe_timeout)
    store_id = Keyword.get(opts, :store_id, :reg_gh)

    # Enable node monitoring
    :ok = :net_kernel.monitor_nodes(true, [:nodedown_reason])
    
    # Schedule initial health probe
    Process.send_after(self(), :health_probe, probe_interval)

    Logger.info("#{Themes.cluster(node())} NodeMonitor started with #{probe_interval}ms intervals")

    {:ok, %{
      probe_interval: probe_interval,
      failure_threshold: failure_threshold,
      probe_timeout: probe_timeout,
      store_id: store_id,
      node_failures: %{},  # Track consecutive failures per node
      last_seen: %{},      # Last successful contact per node
      known_nodes: MapSet.new()
    }}
  end

  @impl true
  def handle_call(:health_status, _from, state) do
    status = %{
      monitored_nodes: MapSet.to_list(state.known_nodes),
      node_failures: state.node_failures,
      last_seen: state.last_seen,
      threshold: state.failure_threshold
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call({:probe_node, node}, _from, state) do
    result = perform_health_probe(node, state.probe_timeout)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:health_probe, state) do
    new_state = perform_health_probe_cycle(state)
    Process.send_after(self(), :health_probe, state.probe_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodedown, node, reason}, state) do
    Logger.warning("#{Themes.cluster(node())} NodeMonitor detected nodedown: #{inspect(node)} (#{inspect(reason)})")
    
    # Immediately handle the failed node
    handle_failed_nodes([node], state.store_id)
    
    # Remove from monitoring state
    new_state = %{state |
      known_nodes: MapSet.delete(state.known_nodes, node),
      node_failures: Map.delete(state.node_failures, node),
      last_seen: Map.delete(state.last_seen, node)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("#{Themes.cluster(node())} NodeMonitor detected nodeup: #{inspect(node)}")
    
    # Reset failure count for recovering node
    new_state = %{state |
      node_failures: Map.delete(state.node_failures, node),
      last_seen: Map.put(state.last_seen, node, System.monotonic_time(:millisecond))
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  ## Private Functions

  defp perform_health_probe_cycle(state) do
    cluster_nodes = get_cluster_nodes(state.store_id)
    new_known_nodes = build_known_nodes_set(cluster_nodes)
    
    {updated_failures, updated_last_seen} = 
      probe_all_nodes(new_known_nodes, state.node_failures, state.last_seen, state)
    
    failed_nodes = extract_failed_nodes(updated_failures, state.failure_threshold)
    maybe_handle_failed_nodes(failed_nodes, state.store_id)
    
    %{state |
      known_nodes: new_known_nodes,
      node_failures: updated_failures,
      last_seen: updated_last_seen
    }
  end

  defp build_known_nodes_set(cluster_nodes) do
    cluster_nodes
    |> MapSet.new()
    |> MapSet.delete(node())  # Don't monitor ourselves
  end

  defp extract_failed_nodes(failures, threshold) do
    failures
    |> Enum.filter(fn {_node, count} -> count >= threshold end)
    |> Enum.map(fn {node, _count} -> node end)
  end

  defp maybe_handle_failed_nodes([], _store_id), do: :ok
  defp maybe_handle_failed_nodes(failed_nodes, store_id) do
    handle_failed_nodes(failed_nodes, store_id)
  end

  defp get_cluster_nodes(store_id) do
    case :khepri_cluster.members(store_id) do
      {:ok, members} ->
        members
        |> Enum.map(fn {_store, node} -> node end)
      
      {:error, _reason} ->
        # Fallback to connected nodes if Khepri is unavailable
        Node.list()
    end
  end

  defp probe_all_nodes(nodes, current_failures, current_last_seen, state) do
    now = System.monotonic_time(:millisecond)
    
    {new_failures, new_last_seen} = 
      nodes
      |> Enum.reduce({current_failures, current_last_seen}, fn node, {failures_acc, seen_acc} ->
        case perform_health_probe(node, state.probe_timeout) do
          :healthy ->
            # Node is healthy, reset failure count and update last seen
            {
              Map.delete(failures_acc, node),
              Map.put(seen_acc, node, now)
            }
          
          :unhealthy ->
            # Node failed probe, increment failure count
            current_count = Map.get(failures_acc, node, 0)
            new_count = current_count + 1
            
            Logger.debug("#{Themes.cluster(node())} Health probe failed for #{inspect(node)} (#{new_count}/#{state.failure_threshold})")
            
            {
              Map.put(failures_acc, node, new_count),
              seen_acc
            }
        end
      end)

    {new_failures, new_last_seen}
  end

  defp perform_health_probe(node, timeout) do
    try do
      # Multi-layer health check
      case check_node_responds(node, timeout) do
        :ok -> check_applications_running(node, timeout)
        :error -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    catch
      _, _ -> :unhealthy
    end
  end

  defp check_node_responds(node, timeout) do
    case :rpc.call(node, :erlang, :node, [], timeout) do
      ^node -> :ok
      _ -> :error
    end
  end

  defp check_applications_running(node, timeout) do
    case :rpc.call(node, :application, :which_applications, [], timeout) do
      {:badrpc, _} -> :unhealthy
      apps when is_list(apps) -> check_ex_esdb_running(apps)
      _ -> :unhealthy
    end
  end

  defp check_ex_esdb_running(apps) do
    case Enum.any?(apps, fn {app, _, _} -> app == :ex_esdb end) do
      true -> :healthy
      false -> :unhealthy
    end
  end

  defp handle_failed_nodes(failed_nodes, store_id) do
    Enum.each(failed_nodes, fn node ->
      Logger.error("#{Themes.cluster(node())} Node #{inspect(node)} detected as failed, initiating cleanup")
      
      # 1. Clean up Swarm registrations for the failed node
      cleanup_swarm_registrations(node)
      
      # 2. Notify cluster about the failure (this could trigger Khepri cleanup)
      notify_cluster_failure(node, store_id)
      
      # 3. Trigger subscription cleanup if needed
      cleanup_subscriptions(node)
    end)
  end

  defp cleanup_swarm_registrations(failed_node) do
    try do
      case get_swarm_registrations() do
        {:ok, names} -> cleanup_failed_node_registrations(names, failed_node)
        :error -> log_swarm_cleanup_warning()
      end
    rescue
      error -> log_swarm_cleanup_error(error)
    end
  end

  defp get_swarm_registrations do
    case :rpc.call(node(), Swarm.Registry, :all_names, [], 5_000) do
      names when is_list(names) -> {:ok, names}
      _ -> :error
    end
  end

  defp cleanup_failed_node_registrations(names, failed_node) do
    failed_registrations = filter_failed_node_registrations(names, failed_node)
    unregister_failed_nodes(failed_registrations, failed_node)
  end

  defp filter_failed_node_registrations(names, failed_node) do
    Enum.filter(names, fn {_name, pid} -> node(pid) == failed_node end)
  end

  defp unregister_failed_nodes(registrations, failed_node) do
    Enum.each(registrations, fn {name, _pid} ->
      Logger.info("#{Themes.cluster(node())} Cleaning up Swarm registration: #{inspect(name)} from failed node #{inspect(failed_node)}")
      Swarm.unregister_name(name)
    end)
  end

  defp log_swarm_cleanup_warning do
    Logger.warning("#{Themes.cluster(node())} Could not retrieve Swarm registrations for cleanup")
  end

  defp log_swarm_cleanup_error(error) do
    Logger.error("#{Themes.cluster(node())} Error during Swarm cleanup: #{inspect(error)}")
  end

  defp notify_cluster_failure(failed_node, store_id) do
    # This could be extended to:
    # 1. Force Khepri to remove the node from cluster
    # 2. Trigger leader election if the failed node was the leader
    # 3. Redistribute data/workers as needed
    
    Logger.info("#{Themes.cluster(node())} Notifying cluster about failed node: #{inspect(failed_node)}")
    
    # For now, just log and let the existing Khepri mechanisms handle it
    # In the future, you could add more aggressive cleanup here
  end

  defp cleanup_subscriptions(failed_node) do
    # Clean up any subscriptions that were managed by the failed node
    # This is application-specific and could be extended based on your needs
    Logger.debug("#{Themes.cluster(node())} Cleaning up subscriptions for failed node: #{inspect(failed_node)}")
  end

  ## Child Spec

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end
end
