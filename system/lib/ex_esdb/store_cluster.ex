defmodule ExESDB.StoreCluster do
  @moduledoc false
  use GenServer

  require Logger

  alias ExESDB.LeaderWorker, as: LeaderWorker
  alias ExESDB.Options, as: Options
  alias ExESDB.StoreCoordinator, as: StoreCoordinator
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  # defp ping?(node) do
  #   case :net_adm.ping(node) do
  #     :pong => true
  #     _ => false
  #   end
  # end

  def leader?(store) do
    case :ra_leaderboard.lookup_leader(store) do
      {_, leader_node} ->
        node() == leader_node

      msg ->
        IO.puts(
          Themes.store_cluster(self(), "🔍 Leader lookup failed on #{node()}: #{inspect(msg)}")
        )

        false
    end
  end

  def activate_leader_worker(store, leader_node) do
    if node() == leader_node do
      IO.puts(
        Themes.store_cluster(
          self(),
          "==> 🚀 This node is the leader, activating LeaderWorker"
        )
      )

      case LeaderWorker.activate(store) do
        :ok ->
          IO.puts(
            Themes.store_cluster(
              self(),
              "✅ LeaderWorker successfully activated"
            )
          )

          :ok

        {:error, reason} ->
          IO.puts(
            Themes.store_cluster(
              self(),
              "❌ Failed to activate LeaderWorker on #{node()}: #{inspect(reason)}"
            )
          )

          {:error, reason}
      end
    end
  end

  defp maybe_perform_leadership_change(previous_leader, leader_node, store, state) do
    cond do
      # Leadership changed to a different node
      previous_leader != nil && previous_leader != leader_node ->
        report_leadership_change(previous_leader, leader_node, store)

        # If we became the leader, activate LeaderWorker
        if node() == leader_node do
          activate_leader_worker(store, leader_node)
        end

        state
        |> Keyword.put(:current_leader, leader_node)

      # First time detecting leader or same leader
      previous_leader == nil ->
        if leader_node != nil do
          IO.puts(Themes.store_cluster(self(), "🏆 LEADER DETECTED 🏆 => #{leader_node}"))

          activate_leader_worker(store, leader_node)
        end

        state |> Keyword.put(:current_leader, leader_node)

      # Same leader, no change needed
      true ->
        state
    end
  end

  defp report_removals(removed_members) do
    if !Enum.empty?(removed_members) do
      Enum.each(removed_members, fn {_store, member} ->
        IO.puts("  ❌ #{inspect(member)} left")
      end)
    end
  end

  defp report_additions(leader, new_members) do
    if !Enum.empty?(new_members) do
      Enum.each(new_members, fn {_store, member} ->
        medal = get_medal(leader, member)
        IO.puts("  ✅ #{medal} #{inspect(member)} joined")
      end)
    end
  end

  defp show_current_members(leader, normalized_current) do
    normalized_current
    |> Enum.each(fn {_store, member} ->
      medal = get_medal(leader, member)
      IO.puts("  #{medal} #{inspect(member)}")
    end)
  end

  defp get_medal(leader, member),
    do: if(member == leader, do: "🏆", else: "🥈")

  defp join_via_connected_nodes(store) do
    case Options.db_type() do
      :cluster ->
        # In cluster mode, use StoreCoordinator if available
        case Process.whereis(ExESDB.StoreCoordinator) do
          nil ->
            IO.puts(
              Themes.store_cluster(
                self(),
                "⚠️ StoreCoordinator not available on #{node()}, trying direct join"
              )
            )

            join_cluster_direct(store)

          _pid ->
            StoreCoordinator.join_cluster(store)
        end

      :single ->
        # In single mode, just ensure the store is started locally
        IO.puts(Themes.store_cluster(self(), "👍 Running in single-node mode on #{node()}"))
        :coordinator

      _ ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "⚠️ Unknown db_type on #{node()}, defaulting to single-node mode"
          )
        )

        :coordinator
    end
  end

  defp join_cluster_direct(store) do
    # Fallback direct cluster join logic for when StoreCoordinator is not available
    connected_nodes = Node.list()

    if Enum.empty?(connected_nodes) do
      IO.puts(
        Themes.store_cluster(
          self(),
          "ℹ️ No connected nodes on #{node()}, starting as single node cluster"
        )
      )

      :no_nodes
    else
      IO.puts(
        Themes.store_cluster(
          self(),
          "🔗 Attempting direct join to cluster from #{node()} via: #{inspect(connected_nodes)}"
        )
      )

      # Try to find a node with an existing cluster
      case find_cluster_node(store, connected_nodes) do
        nil ->
          IO.puts(
            Themes.store_cluster(
              self(),
              "ℹ️ No existing cluster found on #{node()}, starting as coordinator"
            )
          )

          :coordinator

        target_node ->
          join_khepri_cluster(store, target_node)
      end
    end
  end

  defp join_khepri_cluster(store, node) do
    case :khepri_cluster.join(store, node) do
      :ok ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "✅ Successfully joined cluster on #{node()} via #{node}"
          )
        )

        :ok

      {:error, reason} ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "⚠️ Failed to join via #{inspect(node)} from #{node()}: #{inspect(reason)}"
          )
        )

        :failed
    end
  end

  defp report_leadership_change(old_leader, new_leader, _store) do
    IO.puts("\n#{Themes.store_cluster(self(), "🔄 LEADERSHIP CHANGED")}")
    IO.puts("  🔴 Previous leader: #{inspect(old_leader)}")
    IO.puts("  🟢 New leader:      🏆 #{inspect(new_leader)}")

    # Check if we are the new leader
    if node() == new_leader do
      IO.puts("  🚀 This node (#{node()}) is now the leader!")
    else
      IO.puts("  📞 Node #{node()} following new leader: #{inspect(new_leader)}")
    end

    # Also trigger a membership check to show updated leadership in membership
    Process.send(self(), :check_members, [])

    IO.puts("")
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

  defp already_in_cluster?(store) do
    case :khepri_cluster.members(store) do
      {:ok, members} when length(members) > 1 -> true
      _ -> false
    end
  end

  defp should_handle_nodeup?(store) do
    case Options.db_type() do
      :cluster ->
        # In cluster mode, check if we should handle nodeup events
        case Process.whereis(ExESDB.StoreCoordinator) do
          nil ->
            # No coordinator available, check if we're already in a cluster
            not already_in_cluster?(store)

          _pid ->
            ExESDB.StoreCoordinator.should_handle_nodeup?(store)
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
        IO.puts(Themes.store_cluster(self(), "👋 Left cluster from #{node()}"))
        :ok

      {:error, reason} ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "❌ Failed to leave cluster from #{node()}. reason: #{inspect(reason)}"
          )
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
        IO.puts(
          Themes.store_cluster(
            self(),
            "✅ Successfully joined [#{inspect(store)}] cluster from #{node()}"
          )
        )

      # Store registration is now handled by StoreRegistry itself

      :coordinator ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "👑 Acting as cluster coordinator on #{node()}, Khepri cluster already initialized"
          )
        )

      # Store registration is now handled by StoreRegistry itself

      :no_nodes ->
        # Logger.warning(
        #   Themes.store_cluster(
        #     node(),
        #     " => No nodes discovered yet by LibCluster, will retry in #{timeout}ms"
        #   )
        # )
        #
        Process.send_after(self(), :join, timeout)

      :waiting ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "⏳ Waiting for cluster coordinator on #{node()}, will retry in #{timeout * 2}ms"
          )
        )

        Process.send_after(self(), :join, timeout * 2)

      :failed ->
        IO.puts(
          Themes.store_cluster(
            self(),
            "🔄 Failed to join discovered nodes from #{node()}, will retry in #{timeout * 3}ms"
          )
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
          IO.puts("⚠️⚠️ Failed to get store members on #{node()}. reason: #{inspect(reason)} ⚠️⚠️")
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
          IO.puts("\n#{Themes.store_cluster(self(), "🔄 MEMBERSHIP CHANGED on #{node()}")}")

          # Report additions
          new_members = normalized_current -- normalized_previous
          report_additions(leader, new_members)

          # Report removals
          removed_members = normalized_previous -- normalized_current
          report_removals(removed_members)

          # Show current full membership
          IO.puts("\n  Current members:")

          show_current_members(leader, normalized_current)

          IO.puts("")
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
          maybe_perform_leadership_change(previous_leader, leader_node, store, state)

        :undefined ->
          # Only report if we previously had a leader
          if previous_leader != nil do
            IO.puts(
              Themes.store_cluster(self(), "==> ⚠️ LEADERSHIP LOST on #{node()}: No leader found")
            )
          end

          state |> Keyword.put(:current_leader, nil)
      end

    Process.send_after(self(), :check_leader, timeout)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    state[:store_id]
    |> leave()

    msg =
      "🔻🔻 #{Themes.store_cluster(pid, "going down on #{node()} with reason: #{inspect(reason)}")} 🔻🔻"

    IO.puts(msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    IO.puts("#{Themes.store_cluster(pid, "exited on #{node()} with reason: #{inspect(reason)}")}")

    state[:store_id]
    |> leave()

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    IO.puts(
      "#{Themes.store_cluster(self(), "🌐 Detected new node from #{node()}: #{inspect(node)}")}"
    )

    store = state[:store_id]

    # Check if we should handle this nodeup event
    if should_handle_nodeup?(store) do
      IO.puts(
        Themes.store_cluster(
          self(),
          "🔗 Attempting coordinated cluster join from #{node()} due to new node"
        )
      )

      case join_via_connected_nodes(store) do
        :ok ->
          IO.puts(
            Themes.store_cluster(
              self(),
              "✅ Successfully joined cluster from #{node()} after nodeup event"
            )
          )

          # Store registration is now handled by StoreRegistry itself
          # Trigger immediate membership and leadership checks after successful join
          Process.send(self(), :check_members, [])
          Process.send(self(), :check_leader, [])

        :coordinator ->
          IO.puts(
            Themes.store_cluster(
              self(),
              "👑 Acting as coordinator on #{node()} after nodeup event"
            )
          )

          # Store registration is now handled by StoreRegistry itself
          # Trigger immediate leadership check when acting as coordinator
          Process.send(self(), :check_leader, [])

        _ ->
          IO.puts(
            Themes.store_cluster(
              self(),
              "🔄 Coordinated join not successful on #{node()}, will retry later"
            )
          )
      end
    else
      IO.puts(
        Themes.store_cluster(self(), "✅ Already in cluster on #{node()}, ignoring nodeup event")
      )

      # Still trigger membership and leadership checks to detect any changes
      Process.send(self(), :check_members, [])
      Process.send(self(), :check_leader, [])
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    IO.puts(Themes.store_cluster(self(), "🔴 Detected node down from #{node()}: #{inspect(node)}"))
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
    IO.puts(
      Themes.store_cluster(self(), "⚠️ Terminating on #{node()} with reason: #{inspect(reason)}")
    )

    state[:store_id]
    |> leave()

    :ok
  end

  @impl true
  def init(config) do
    timeout = config[:timeout] || 1000
    state = Keyword.put(config, :timeout, timeout)
    IO.puts(Themes.store_cluster(self(), "🚀 is UP on #{node()}"))
    Process.flag(:trap_exit, true)

    # Subscribe to LibCluster events
    :ok = :net_kernel.monitor_nodes(true)

    Process.send_after(self(), :join, timeout)
    Process.send_after(self(), :check_members, 10 * timeout)
    Process.send_after(self(), :check_leader, timeout)
    {:ok, state}
  end

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 10_000,
      type: :worker
    }
  end
end
