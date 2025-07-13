defmodule ExESDB.KhepriCluster do
  @moduledoc false
  use GenServer

  require Logger

  alias ExESDB.LeaderWorker, as: LeaderWorker
  alias ExESDB.Options, as: Options

  # defp ping?(node) do
  #   case :net_adm.ping(node) do
  #     :pong => true
  #     _ => false
  #   end
  # end

  def leader?(store) do
    Logger.debug("checking if node is leader",
      component: :cluster,
      pid: node()
    )

    case :ra_leaderboard.lookup_leader(store) do
      {_, leader_node} ->
        Logger.debug("node is leader: #{inspect(leader_node)}",
          component: :cluster,
          pid: node()
        )
        node() == leader_node

      msg ->
        Logger.debug("leader lookup failed: #{inspect(msg)}",
          component: :cluster,
          pid: node()
        )
        false
    end
  end

  defp get_medal(leader, member),
    do: if(member == leader, do: "🏆", else: "🥈")

  defp join_via_connected_nodes(store) do
    case Options.db_type() do
      :cluster ->
        # In cluster mode, use ClusterCoordinator if available
        case Process.whereis(ExESDB.ClusterCoordinator) do
          nil ->
            Logger.warning("ClusterCoordinator not available, trying direct join",
              component: :cluster,
              pid: node()
            )

            join_cluster_direct(store)

          _pid ->
            ExESDB.ClusterCoordinator.join_cluster(store)
        end

      :single ->
        # In single mode, just ensure the store is started locally
        Logger.info("Running in single-node mode",
          component: :cluster,
          pid: node()
        )
        :coordinator

      _ ->
        Logger.warning("Unknown db_type, defaulting to single-node mode",
          component: :cluster,
          pid: node()
        )

        :coordinator
    end
  end

  defp join_cluster_direct(store) do
    # Fallback direct cluster join logic for when ClusterCoordinator is not available
    connected_nodes = Node.list()

    if Enum.empty?(connected_nodes) do
      Logger.info("No connected nodes, starting as single node cluster",
        component: :cluster,
        pid: node()
      )

      :no_nodes
    else
      Logger.info("Attempting direct join to cluster via: #{inspect(connected_nodes)}",
        component: :cluster,
        pid: node()
      )

      # Try to find a node with an existing cluster
      case find_cluster_node(store, connected_nodes) do
        nil ->
          Logger.info("No existing cluster found, starting as coordinator",
            component: :cluster,
            pid: node()
          )

          :coordinator

        target_node ->
          case :khepri_cluster.join(store, target_node) do
            :ok ->
              Logger.info("Successfully joined cluster via #{inspect(target_node)}",
                component: :cluster,
                pid: node()
              )

              :ok

            {:error, reason} ->
              Logger.warning("Failed to join via #{inspect(target_node)}: #{inspect(reason)}",
                component: :cluster,
                pid: node()
              )

              :failed
          end
      end
    end
  end

  defp find_cluster_node(store, nodes) do
    Enum.find(nodes, fn node ->
      try do
        case :rpc.call(node, :khepri_cluster, :members, [store], 5000) do
          {:ok, members} when members != [] -> true
          _ -> false
        end
      rescue
        _ -> false
      catch
        _, _ -> false
      end
    end)
  end

  defp should_handle_nodeup?(store) do
    case Options.db_type() do
      :cluster ->
        # In cluster mode, check if we should handle nodeup events
        case Process.whereis(ExESDB.ClusterCoordinator) do
          nil ->
            # No coordinator available, check if we're already in a cluster
            case :khepri_cluster.members(store) do
              {:ok, members} when length(members) > 1 -> false
              _ -> true
            end

          _pid ->
            ExESDB.ClusterCoordinator.should_handle_nodeup?(store)
        end

      :single ->
        # In single mode, never handle nodeup events for clustering
        false

      _ ->
        false
    end
  end

  defp leave(store) do
    case store |> :khepri_cluster.reset() do
      :ok ->
        Logger.info("Left cluster",
          component: :cluster,
          pid: node()
        )
        :ok

      {:error, reason} ->
        Logger.error("Failed to leave cluster. reason: #{inspect(reason)}",
          component: :cluster,
          pid: node()
        )

        {:error, reason}
    end
  end

  defp members(store),
    do:
      store
      |> :khepri_cluster.members()

  @impl true
  def handle_info(:join, state) do
    store = state[:store_id]
    timeout = state[:timeout]

    case join_via_connected_nodes(store) do
      :ok ->
        Logger.info("Successfully joined Khepri cluster",
          component: :cluster,
          pid: node()
        )

      :coordinator ->
        Logger.info("Acting as cluster coordinator, Khepri cluster already initialized",
          component: :cluster,
          pid: node()
        )

      :no_nodes ->
        Logger.warning("No nodes discovered yet by LibCluster, will retry in #{timeout}ms",
          component: :cluster,
          pid: node()
        )

        Process.send_after(self(), :join, timeout)

      :waiting ->
        Logger.alert("Waiting for cluster coordinator, will retry in #{timeout * 2}ms",
          component: :cluster,
          pid: node()
        )

        Process.send_after(self(), :join, timeout * 2)

      :failed ->
        Logger.alert("Failed to join discovered nodes, will retry in #{timeout * 3}ms",
          component: :cluster,
          pid: node()
        )

        Process.send_after(self(), :join, timeout * 3)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:check_members, state) do
    leader = Keyword.get(state, :current_leader)
    store = state[:store_id]
    previous_members = Keyword.get(state, :previous_members, [])

    case store |> members() do
      {:error, reason} ->
        # Only log errors if they're different from the last error
        last_error = Keyword.get(state, :last_member_error)

        if last_error != reason do
          Logger.warning("⚠️⚠️ Failed to get store members. reason: #{inspect(reason)} ⚠️⚠️",
            component: :cluster,
            pid: self()
          )
        end

        new_state = Keyword.put(state, :last_member_error, reason)
        Process.send_after(self(), :check_members, 5 * state[:timeout])
        {:noreply, new_state}

      {:ok, current_members} ->
        # Normalize members for comparison (sort by member name)
        normalized_current = Enum.sort_by(current_members, fn {_store, member} -> member end)
        normalized_previous = Enum.sort_by(previous_members, fn {_store, member} -> member end)

        # Only report if membership has changed
        if normalized_current != normalized_previous do
          Logger.info("MEMBERSHIP CHANGED",
            component: :cluster,
            pid: self(),
            arrow: true
          )

          # Report additions
          new_members = normalized_current -- normalized_previous

          if !Enum.empty?(new_members) do
            Enum.each(new_members, fn {_store, member} ->
              medal = get_medal(leader, member)
              Logger.info("✅ #{medal} #{inspect(member)} joined",
                component: :cluster,
                pid: self(),
                indent: 1
              )
            end)
          end

          # Report removals
          removed_members = normalized_previous -- normalized_current

          if !Enum.empty?(removed_members) do
            Enum.each(removed_members, fn {_store, member} ->
              Logger.info("❌ #{inspect(member)} left",
                component: :cluster,
                pid: self(),
                indent: 1
              )
            end)
          end

          # Show current full membership
          Logger.info("Current members:",
            component: :cluster,
            pid: self(),
            indent: 1
          )

          normalized_current
          |> Enum.each(fn {_store, member} ->
            medal = get_medal(leader, member)
            Logger.info("#{medal} #{inspect(member)}",
              component: :cluster,
              pid: self(),
              indent: 1
            )
          end)
        end

        # Update state with current members and clear any previous error
        new_state =
          state
          |> Keyword.put(:previous_members, current_members)
          |> Keyword.delete(:last_member_error)

        Process.send_after(self(), :check_members, 5 * state[:timeout])
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:check_leader, state) do
    timeout = state[:timeout]
    previous_leader = Keyword.get(state, :current_leader)
    store = Keyword.get(state, :store_id)

    new_state =
      case :ra_leaderboard.lookup_leader(store) do
        {_, leader_node} ->
          cond do
            # Leadership changed to a different node
            previous_leader != nil && previous_leader != leader_node ->
              report_leadership_change(previous_leader, leader_node, store)

              # If we became the leader, activate LeaderWorker
              if node() == leader_node do
                store |> LeaderWorker.activate()
              end

              state |> Keyword.put(:current_leader, leader_node)

            # First time detecting leader or same leader
            previous_leader == nil ->
              if leader_node != nil do
                Logger.info("LEADER DETECTED: 🏆 #{inspect(leader_node)}",
                  component: :cluster,
                  pid: self(),
                  arrow: true
                )

                # If we are the initial leader, activate LeaderWorker
                if node() == leader_node do
                  Logger.info("🚀 This node is the leader, activating LeaderWorker",
                    component: :cluster,
                    pid: self(),
                    arrow: true
                  )

                  store |> LeaderWorker.activate()
                end
              end

              state |> Keyword.put(:current_leader, leader_node)

            # Same leader, no change needed
            true ->
              state
          end

        :undefined ->
          # Only report if we previously had a leader
          if previous_leader != nil do
            Logger.warning("⚠️ LEADERSHIP LOST: No leader found",
              component: :cluster,
              pid: self(),
              arrow: true
            )
          end

          state |> Keyword.put(:current_leader, nil)
      end

    Process.send_after(self(), :check_leader, timeout)
    {:noreply, new_state}
  end

  defp report_leadership_change(old_leader, new_leader, _store) do
    Logger.info("🔄 LEADERSHIP CHANGED",
      component: :cluster,
      pid: self(),
      arrow: true
    )
    
    Logger.info("🔴 Previous leader: #{inspect(old_leader)}",
      component: :cluster,
      pid: self(),
      indent: 1
    )
    
    Logger.info("🟢 New leader:      🏆 #{inspect(new_leader)}",
      component: :cluster,
      pid: self(),
      indent: 1
    )

    # Check if we are the new leader
    if node() == new_leader do
      Logger.info("🚀 This node is now the leader!",
        component: :cluster,
        pid: self(),
        indent: 1
      )
    else
      Logger.info("📞 Following new leader: #{inspect(new_leader)}",
        component: :cluster,
        pid: self(),
        indent: 1
      )
    end

    # Also trigger a membership check to show updated leadership in membership
    Process.send(self(), :check_members, [])
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    state[:store_id]
    |> leave()

    Logger.warning("🔻🔻 going down with reason: #{inspect(reason)} 🔻🔻",
      component: :cluster,
      pid: pid
    )
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.debug("exited with reason: #{inspect(reason)}",
      component: :cluster,
      pid: pid
    )

    state[:store_id]
    |> leave()

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("detected new node: #{inspect(node)}",
      component: :cluster,
      pid: self()
    )

    store = state[:store_id]

    # Check if we should handle this nodeup event
    if should_handle_nodeup?(store) do
      Logger.info("attempting coordinated cluster join due to new node",
        component: :cluster,
        pid: node()
      )

      case join_via_connected_nodes(store) do
        :ok ->
          Logger.info("successfully joined cluster after nodeup event",
            component: :cluster,
            pid: node()
          )
          # Trigger immediate membership and leadership checks after successful join
          Process.send(self(), :check_members, [])
          Process.send(self(), :check_leader, [])

        :coordinator ->
          Logger.info("acting as coordinator after nodeup event",
            component: :cluster,
            pid: node()
          )
          # Trigger immediate leadership check when acting as coordinator
          Process.send(self(), :check_leader, [])

        _ ->
          Logger.debug("coordinated join not successful, will retry later",
            component: :cluster,
            pid: node()
          )
      end
    else
      Logger.debug("already in cluster, ignoring nodeup event",
        component: :cluster,
        pid: node()
      )
      # Still trigger membership and leadership checks to detect any changes
      Process.send(self(), :check_members, [])
      Process.send(self(), :check_leader, [])
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("detected node down: #{inspect(node)}",
      component: :cluster,
      pid: self()
    )
    # Trigger immediate membership and leadership checks after node down event
    Process.send(self(), :check_members, [])
    Process.send(self(), :check_leader, [])
    {:noreply, state}
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, state}
  end

  ############# PLUMBING #############
  @impl true
  def terminate(reason, state) do
    Logger.warning("terminating with reason: #{inspect(reason)}",
      component: :cluster,
      pid: self()
    )

    state[:store_id]
    |> leave()

    :ok
  end

  @impl true
  def init(config) do
    timeout = config[:timeout] || 1000
    state = Keyword.put(config, :timeout, timeout)
    Logger.info("is UP",
      component: :cluster,
      pid: self()
    )
    Process.flag(:trap_exit, true)

    # Subscribe to LibCluster events
    :ok = :net_kernel.monitor_nodes(true)

    Process.send_after(self(), :join, timeout)
    Process.send_after(self(), :check_members, 10 * timeout)
    Process.send_after(self(), :check_leader, timeout)
    {:ok, state}
  end

  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  def child_spec(opts),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 10_000,
      type: :worker
    }
end
