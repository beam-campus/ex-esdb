defmodule ExESDB.ConsistencyChecker do
  @moduledoc """
  Provides tools for verifying consistency across ExESDB cluster stores.
  
  This module leverages Khepri and Ra APIs to verify that stores are consistent
  across cluster nodes, detect split-brain scenarios, and ensure data integrity.
  """
  
  require Logger

  @type store_id :: atom()
  @type node_name :: atom()
  @type consistency_result :: :consistent | :inconsistent | :error
  @type check_result :: {:ok, map()} | {:error, term()}

  @doc """
  Performs a comprehensive consistency check across all cluster nodes for a given store.
  
  ## Returns
  - `{:ok, report}` - Detailed consistency report
  - `{:error, reason}` - Error occurred during check
  
  ## Example
      iex> ExESDB.ConsistencyChecker.verify_cluster_consistency(:my_store)
      {:ok, %{
        status: :consistent,
        nodes_checked: 3,
        leader: :"node1@host",
        members: [:"node1@host", :"node2@host", :"node3@host"],
        raft_status: :healthy,
        potential_issues: []
      }}
  """
  @spec verify_cluster_consistency(store_id()) :: check_result()
  def verify_cluster_consistency(store_id) do
    Logger.info("Starting consistency check for store: #{inspect(store_id)}")
    
    try do
      with {:ok, local_members} <- get_cluster_members(store_id),
           {:ok, leader_info} <- get_leader_info(store_id),
           {:ok, cross_node_check} <- verify_cross_node_consistency(store_id, local_members),
           {:ok, raft_status} <- check_raft_status(store_id) do
        
        report = compile_consistency_report(store_id, local_members, leader_info, cross_node_check, raft_status)
        Logger.info("Consistency check completed for store: #{inspect(store_id)}")
        {:ok, report}
      else
        {:error, reason} = error ->
          Logger.error("Consistency check failed for store #{inspect(store_id)}: #{inspect(reason)}")
          error
      end
    rescue
      error ->
        Logger.error("Exception during consistency check: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  @doc """
  Quick health check to verify if a store is accessible and responsive across nodes.
  """
  @spec quick_health_check(store_id()) :: check_result()
  def quick_health_check(store_id) do
    try do
      case :khepri_cluster.members(store_id) do
        {:ok, members} when members != [] ->
          {:ok, %{
            status: :healthy,
            store_id: store_id,
            member_count: length(members),
            members: members
          }}
        {:ok, []} ->
          {:error, :no_members}
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, {:exception, error}}
    end
  end

  @doc """
  Verifies that all nodes agree on cluster membership.
  """
  @spec verify_membership_consensus(store_id()) :: check_result()
  def verify_membership_consensus(store_id) do
    with {:ok, local_members} <- get_cluster_members(store_id) do
      nodes = extract_nodes_from_members(local_members)
      membership_views = get_membership_views_from_nodes(store_id, nodes)
      
      case analyze_membership_consensus(membership_views) do
        :consensus ->
          {:ok, %{
            status: :consensus,
            nodes_checked: length(nodes),
            consistent_view: local_members
          }}
        {:split_brain, conflicts} ->
          {:ok, %{
            status: :split_brain_detected,
            conflicts: conflicts,
            nodes_checked: length(nodes)
          }}
        {:partial_failure, failed_nodes} ->
          {:ok, %{
            status: :partial_check,
            failed_nodes: failed_nodes,
            nodes_checked: length(nodes)
          }}
      end
    end
  end

  @doc """
  Checks Raft log consistency across cluster members.
  This is a more intensive check that examines log indices and terms.
  """
  @spec check_raft_log_consistency(store_id()) :: check_result()
  def check_raft_log_consistency(store_id) do
    with {:ok, members} <- get_cluster_members(store_id),
         {:ok, log_info} <- gather_raft_log_info(store_id, members) do
      
      consistency_analysis = analyze_raft_log_consistency(log_info)
      
      {:ok, %{
        store_id: store_id,
        raft_logs: log_info,
        consistency: consistency_analysis
      }}
    end
  end

  @doc """
  Monitors consistency over time and reports any deviations.
  """
  @spec start_consistency_monitoring(store_id(), pos_integer()) :: {:ok, pid()}
  def start_consistency_monitoring(store_id, interval_ms \\ 30_000) do
    Task.start(fn ->
      monitor_consistency_loop(store_id, interval_ms)
    end)
  end

  ## Private Functions

  defp get_cluster_members(store_id) do
    case :khepri_cluster.members(store_id) do
      {:ok, members} -> {:ok, members}
      {:error, reason} -> {:error, {:members_failed, reason}}
    end
  end

  defp get_leader_info(store_id) do
    case :ra_leaderboard.lookup_leader(store_id) do
      {store_id, leader_node} when is_atom(leader_node) ->
        {:ok, %{leader: leader_node, store: store_id}}
      other ->
        {:error, {:unexpected_leader_response, other}}
    end
  end

  defp verify_cross_node_consistency(store_id, local_members) do
    nodes = extract_nodes_from_members(local_members)
    
    cross_checks = Enum.map(nodes, fn node ->
      case :rpc.call(node, :khepri_cluster, :members, [store_id], 5000) do
        {:ok, remote_members} ->
          {node, :ok, remote_members}
        {:error, reason} ->
          {node, :error, reason}
        {:badrpc, reason} ->
          {node, :rpc_error, reason}
      end
    end)
    
    {:ok, cross_checks}
  end

  defp check_raft_status(store_id) do
    # Check if we can query Ra status
    case :ra.members({store_id, node()}) do
      {_status, members, leader} when is_list(members) ->
        {:ok, %{
          status: :healthy,
          members: members,
          leader: leader,
          quorum_size: calculate_quorum_size(length(members))
        }}
      {_status, reason} ->
        Logger.warning("Raft status check failed: #{inspect(reason)}")
        {:ok, %{status: :error, reason: reason}}
    end
  rescue
    error ->
      Logger.warning("Exception checking Raft status: #{inspect(error)}")
      {:ok, %{status: :exception, error: error}}
  end

  defp extract_nodes_from_members(members) do
    Enum.map(members, fn {_store, node} -> node end)
  end

  defp get_membership_views_from_nodes(store_id, nodes) do
    Enum.map(nodes, fn node ->
      case :rpc.call(node, :khepri_cluster, :members, [store_id], 5000) do
        {:ok, members} -> {node, :ok, members}
        error -> {node, :error, error}
      end
    end)
  end

  defp analyze_membership_consensus(membership_views) do
    {successful, failed} = Enum.split_with(membership_views, fn {_node, status, _data} -> 
      status == :ok 
    end)
    
    if length(failed) > 0 do
      failed_nodes = Enum.map(failed, fn {node, _status, _data} -> node end)
      {:partial_failure, failed_nodes}
    else
      # Check if all successful views are identical
      member_lists = Enum.map(successful, fn {_node, :ok, members} -> 
        Enum.sort(members) 
      end)
      
      case Enum.uniq(member_lists) do
        [_single_view] -> :consensus
        multiple_views -> {:split_brain, %{views: multiple_views, nodes: successful}}
      end
    end
  end

  defp gather_raft_log_info(_store_id, members) do
    log_info = Enum.map(members, fn {store, node} ->
      case :rpc.call(node, :ra, :log_overview, [{store, node}], 5000) do
        {:ok, overview} -> {node, :ok, overview}
        error -> {node, :error, error}
      end
    end)
    
    {:ok, log_info}
  end

  defp analyze_raft_log_consistency(log_info) do
    {successful, failed} = Enum.split_with(log_info, fn {_node, status, _data} -> 
      status == :ok 
    end)
    
    if length(failed) > 0 do
      %{
        status: :partial_failure,
        failed_nodes: Enum.map(failed, fn {node, _status, _data} -> node end),
        successful_count: length(successful)
      }
    else
      # Analyze log terms and indices for consistency
      log_details = Enum.map(successful, fn {node, :ok, overview} ->
        {node, extract_log_details(overview)}
      end)
      
      %{
        status: :analyzed,
        log_details: log_details,
        consistency: check_log_term_consistency(log_details)
      }
    end
  end

  defp extract_log_details(overview) do
    # Extract relevant details from Ra log overview
    # This is a simplified version - actual implementation would need
    # to handle the specific structure returned by :ra.log_overview
    %{
      last_index: Map.get(overview, :last_index, :unknown),
      last_term: Map.get(overview, :last_term, :unknown),
      commit_index: Map.get(overview, :commit_index, :unknown)
    }
  end

  defp check_log_term_consistency(log_details) do
    # Check if all nodes have consistent log terms and indices
    terms = Enum.map(log_details, fn {_node, details} -> details.last_term end)
    indices = Enum.map(log_details, fn {_node, details} -> details.last_index end)
    
    %{
      term_consistency: length(Enum.uniq(terms)) <= 1,
      index_range: {Enum.min(indices), Enum.max(indices)},
      details: log_details
    }
  end

  defp calculate_quorum_size(member_count) when member_count > 0 do
    div(member_count, 2) + 1
  end

  defp compile_consistency_report(store_id, members, leader_info, cross_node_check, raft_status) do
    issues = detect_potential_issues(members, leader_info, cross_node_check, raft_status)
    
    overall_status = if Enum.empty?(issues), do: :consistent, else: :inconsistent
    
    %{
      store_id: store_id,
      timestamp: DateTime.utc_now(),
      status: overall_status,
      nodes_checked: length(members),
      leader: Map.get(leader_info, :leader),
      members: members,
      raft_status: raft_status,
      cross_node_verification: cross_node_check,
      potential_issues: issues,
      recommendations: generate_recommendations(issues)
    }
  end

  defp detect_potential_issues(members, leader_info, cross_node_check, _raft_status) do
    issues = []
    
    # Check for missing leader
    issues = if Map.get(leader_info, :leader) == nil do
      [:no_leader | issues]
    else
      issues
    end
    
    # Check for node communication failures
    failed_nodes = Enum.filter(cross_node_check, fn {_node, status, _data} -> 
      status != :ok 
    end)
    
    issues = if length(failed_nodes) > 0 do
      [{:communication_failures, failed_nodes} | issues]
    else
      issues
    end
    
    # Check for membership inconsistencies
    member_views = Enum.map(cross_node_check, fn
      {node, :ok, remote_members} -> {node, remote_members}
      {node, _error, _} -> {node, []}
    end)
    
    local_members = Enum.sort(members)
    inconsistent_views = Enum.filter(member_views, fn {_node, remote_members} ->
      Enum.sort(remote_members) != local_members
    end)
    
    issues = if length(inconsistent_views) > 0 do
      [{:membership_inconsistency, inconsistent_views} | issues]
    else
      issues
    end
    
    issues
  end

  defp generate_recommendations(issues) do
    Enum.flat_map(issues, fn
      :no_leader ->
        ["Check cluster connectivity and ensure quorum is available"]
      
      {:communication_failures, failed_nodes} ->
        nodes = Enum.map(failed_nodes, fn {node, _status, _data} -> node end)
        ["Investigate connectivity issues with nodes: #{inspect(nodes)}"]
      
      {:membership_inconsistency, _inconsistent_views} ->
        ["Resolve membership inconsistencies - potential split-brain scenario detected"]
      
      _ ->
        ["Review cluster configuration and connectivity"]
    end)
  end

  defp monitor_consistency_loop(store_id, interval_ms) do
    case verify_cluster_consistency(store_id) do
      {:ok, %{status: :consistent}} ->
        Logger.debug("Consistency monitor: Store #{inspect(store_id)} is consistent")
      
      {:ok, %{status: :inconsistent, potential_issues: issues}} ->
        Logger.warning("Consistency monitor: Issues detected in store #{inspect(store_id)}: #{inspect(issues)}")
      
      {:error, reason} ->
        Logger.error("Consistency monitor: Failed to check store #{inspect(store_id)}: #{inspect(reason)}")
    end
    
    Process.sleep(interval_ms)
    monitor_consistency_loop(store_id, interval_ms)
  end
end
