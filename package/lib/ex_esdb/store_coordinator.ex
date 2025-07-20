defmodule ExESDB.StoreCoordinator do
  @moduledoc """
  GenServer responsible for coordinating Khepri cluster formation and preventing split-brain scenarios.

  This module handles:
  - Detecting existing clusters
  - Coordinator election
  - Coordinated cluster joining
  - Split-brain prevention
  """
  use GenServer

  require Logger
  
  alias ExESDB.StoreNaming, as: StoreNaming
  alias ExESDB.Themes, as: Themes

  @doc """
  Attempts to join a Khepri cluster using coordinated approach to prevent split-brain.
  Returns one of: :ok, :coordinator, :no_nodes, :waiting, :failed
  """
  def join_cluster(store) do
    name = StoreNaming.genserver_name(__MODULE__, store)
    GenServer.call(name, {:join_cluster, store}, 10_000)
  end

  @doc """
  Checks if this node should handle nodeup events (i.e., not already in a cluster)
  """
  def should_handle_nodeup?(store) do
    name = StoreNaming.genserver_name(__MODULE__, store)
    GenServer.call(name, {:should_handle_nodeup, store}, 5_000)
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    IO.puts(Themes.store_coordinator(self(), "is UP"))
    {:ok, %{}}
  end

  @impl true
  def handle_call({:join_cluster, store}, _from, state) do
    result = join_via_connected_nodes(store)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:should_handle_nodeup, store}, _from, state) do
    result = should_handle_nodeup_event?(store)
    {:reply, result, state}
  end

  @impl true
  def terminate(reason, _state) do
    IO.puts(
      Themes.store_coordinator(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}")
    )

    :ok
  end

  ## Private Functions

  defp join_via_connected_nodes(store) do
    # Get all connected nodes from LibCluster
    connected_nodes = Node.list()

    if Enum.empty?(connected_nodes) do
      # Logger.info(
      #   Themes.store_coordinator(
      #     node(),
      #     "=> No connected nodes found via LibCluster, starting as single node cluster"
      #   )
      # )

      :no_nodes
    else
      IO.puts(
        Themes.store_coordinator(
          self(),
          "[#{node()}] Attempting to join Khepri cluster via LibCluster discovered nodes: #{inspect(connected_nodes)}"
        )
      )

      # Find nodes that already have Khepri clusters running
      cluster_nodes = find_existing_cluster_nodes(store, connected_nodes)

      case cluster_nodes do
        [] ->
          # No existing clusters found, check if we should be the coordinator
          handle_no_existing_clusters(connected_nodes)

        [target_node | _] ->
          # Found existing cluster, join it
          join_existing_cluster(store, target_node)
      end
    end
  end

  defp handle_no_existing_clusters(connected_nodes) do
    if should_be_store_coordinator(connected_nodes) do
      IO.puts(
        Themes.store_coordinator(
          self(),
          "[#{node()}] Elected as cluster coordinator, starting new cluster"
        )
      )

      :coordinator
    else
      IO.puts(
        Themes.store_coordinator(
          self(),
          "[#{node()}] Waiting for cluster coordinator to establish cluster"
        )
      )

      :waiting
    end
  end

  defp join_existing_cluster(store, target_node) do
    log_join_attempt(target_node)
    
    case :khepri_cluster.join(store, target_node) do
      :ok ->
        log_join_success(target_node)
        verify_cluster_membership(store)
      
      {:error, reason} ->
        log_join_failure(target_node, reason)
        :failed
    end
  end

  defp log_join_attempt(target_node) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] Joining existing ExESDB cluster via: #{target_node}"
      )
    )
  end

  defp log_join_success(target_node) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] 🎯 Successfully joined existing Khepri cluster via #{target_node}"
      )
    )
  end

  defp log_join_failure(target_node, reason) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] ⚠️ Failed to join via #{target_node}: #{inspect(reason)}"
      )
    )
  end

  defp verify_cluster_membership(store) do
    case :khepri_cluster.members(store) do
      {:ok, members} when length(members) > 1 ->
        log_verification_success(length(members))
        :ok

      {:ok, [_single]} ->
        log_verification_warning()
        :ok

      {:error, verify_reason} ->
        log_verification_error(verify_reason)
        :ok
    end
  end

  defp log_verification_success(member_count) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] ✅ Cluster join verified, now part of #{member_count}-node cluster"
      )
    )
  end

  defp log_verification_warning do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] ⚠️ Join appeared successful but still only 1 member, may need retry"
      )
    )
  end

  defp log_verification_error(reason) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] ❌ Join succeeded but verification failed: #{inspect(reason)}"
      )
    )
  end

  defp find_existing_cluster_nodes(store, connected_nodes) do
    Enum.filter(connected_nodes, &has_active_cluster?(&1, store))
  end

  defp has_active_cluster?(node, store) do
    case safe_cluster_check(node, store) do
      {:ok, members} when members != [] ->
        log_cluster_found(node, length(members))
        true

      {:ok, []} ->
        log_empty_cluster(node)
        false

      {:error, reason} ->
        log_cluster_check_failed(node, reason)
        false

      other ->
        log_unexpected_response(node, other)
        false
    end
  end

  defp safe_cluster_check(node, store) do
    try do
      :rpc.call(node, :khepri_cluster, :members, [store], 5000)
    rescue
      e ->
        log_cluster_check_exception(node, e)
        {:error, {:exception, e}}
    catch
      type, reason ->
        log_cluster_check_caught(node, type, reason)
        {:error, {:caught, type, reason}}
    end
  end

  defp log_cluster_found(node, member_count) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] 🔍 Found existing cluster on #{node} with #{member_count} members"
      )
    )
  end

  defp log_empty_cluster(node) do
    IO.puts(
      Themes.store_coordinator(self(), "[#{node()}] 🔍 Node #{node} has empty cluster")
    )
  end

  defp log_cluster_check_failed(node, reason) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] 🔍 Node #{node} cluster check failed: #{inspect(reason)}"
      )
    )
  end

  defp log_unexpected_response(node, response) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] 🔍 Node #{node} unexpected response: #{inspect(response)}"
      )
    )
  end

  defp log_cluster_check_exception(node, exception) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] 🔍 Node #{node} cluster check exception: #{inspect(exception)}"
      )
    )
  end

  defp log_cluster_check_caught(node, type, reason) do
    IO.puts(
      Themes.store_coordinator(
        self(),
        "[#{node()}] 🔍 Node #{node} cluster check caught: #{inspect(type)} #{inspect(reason)}"
      )
    )
  end

  defp should_be_store_coordinator(connected_nodes) do
    # Use deterministic election: lowest node name becomes coordinator
    all_nodes =
      [node() | connected_nodes]
      |> Enum.sort()

    node() == List.first(all_nodes)
  end

  defp should_handle_nodeup_event?(store) do
    # Check if we're already part of a cluster
    case :khepri_cluster.members(store) do
      {:ok, members} when members != [] ->
        # We're already in a cluster, no need to handle nodeup
        false

      _ ->
        # We're not in a cluster or only have ourselves, should handle nodeup
        true
    end
  end

  ## Child Spec and Startup

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)

    %{
      id: ExESDB.StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)

    GenServer.start_link(__MODULE__, opts, name: name)
  end
end
