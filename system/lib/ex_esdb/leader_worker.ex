defmodule ExESDB.LeaderWorker do
  @moduledoc """
    This module contains the leader's reponsibilities for the cluster.
  """
  use GenServer
  require Logger
  alias ExESDB.Emitters
  alias ExESDB.SubscriptionsReader, as: SubsR
  alias ExESDB.SubscriptionsWriter, as: SubsW
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming
  ############ API ############
  @doc """
  Activates the LeaderWorker for the given store.
  
  This function is called when this node becomes the cluster leader.
  """
  def activate(store) do
    # For backward compatibility, try to find the LeaderWorker process
    # First try with store-specific naming, then fall back to global naming
    name = StoreNaming.genserver_name(__MODULE__, store)
    
    process_name = case Process.whereis(name) do
      nil ->
        # Fall back to global naming for backward compatibility
        case Process.whereis(__MODULE__) do
          nil ->
            {:error, :not_found}
          _pid ->
            __MODULE__
        end
      _pid ->
        name
    end
    
    case process_name do
      {:error, :not_found} ->
        {:error, :not_found}
      valid_name ->
        # Save default subscriptions synchronously
        case GenServer.call(valid_name, {:save_default_subscriptions, store}, 10_000) do
          {:ok, _result} ->
            # Now activate leadership responsibilities
            GenServer.cast(valid_name, {:activate, store})
            IO.puts(Themes.leader_worker(self(), "✅ LeaderWorker activated successfully"))
            :ok
          {:error, reason} ->
            IO.puts(Themes.leader_worker(self(), "❌ Failed to activate LeaderWorker: #{inspect(reason)}"))
            {:error, reason}
        end
    end
  rescue
    error ->
      IO.puts(Themes.leader_worker(self(), "❌ LeaderWorker activation failed with error: #{inspect(error)}"))
      {:error, error}
  catch
    :exit, reason ->
      IO.puts(Themes.leader_worker(self(), "❌ LeaderWorker activation failed with exit: #{inspect(reason)}"))
      {:error, reason}
  end

  ########## HANDLE_CAST ##########
  @impl true
  def handle_cast({:activate, store}, state) do
    IO.puts("\n#{Themes.leader_worker(self(), "🚀 ACTIVATING LEADERSHIP RESPONSIBILITIES")}")
    IO.puts("  🏆 Node: #{inspect(node())}")
    IO.puts("  📊 Store: #{inspect(store)}")

    subscriptions =
      store
      |> SubsR.get_subscriptions()

    subscription_count = Enum.count(subscriptions)

    case subscription_count do
      0 ->
        IO.puts("  📝 No active subscriptions to manage")

      1 ->
        IO.puts("  📝 Managing 1 active subscription")

      num ->
        IO.puts("  📝 Managing #{num} active subscriptions")
    end

    if subscription_count > 0 do
      IO.puts("\n  Starting emitters for active subscriptions:")

      # Check if EmitterPools is available
      emitter_pools_name = StoreNaming.partition_name(ExESDB.EmitterPools, store)
      case Process.whereis(emitter_pools_name) do
        nil ->
          IO.puts("    ⚠️  EmitterPools not available, skipping emitter startup")
          IO.puts("    ℹ️  EmitterPools will be started when EmitterSystem is ready")
        
        _pid ->
          subscriptions
          |> Enum.each(fn {key, subscription} ->
            IO.puts("    ⚙️  Starting emitter for: #{inspect(key)}")

            case Emitters.start_emitter_pool(store, subscription) do
              {:ok, _pid} ->
                IO.puts("    ✅ Successfully started emitter pool for #{inspect(key)}")
              {:error, {:already_started, _pid}} ->
                IO.puts("    ✅ Emitter pool already running for #{inspect(key)}")
              {:error, reason} ->
                IO.puts("    ❌ Failed to start emitter pool for #{inspect(key)}: #{inspect(reason)}")
            end
          end)
      end
    end

    IO.puts("\n  ✅ Leadership activation complete\n")

    {:noreply, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Leader received unexpected CAST: #{inspect(msg)}")
    {:noreply, state}
  end

  ################ HANDLE_INFO ############
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Leader received unexpected INFO: #{inspect(msg)}")
    {:noreply, state}
  end

  ############# HANDLE_CALL ##########
  @impl true
  def handle_call({:save_default_subscriptions, store}, _from, state) do
    try do
      res =
        store
        |> SubsW.put_subscription_sync(:by_stream, "$all", "all-events")

      {:reply, res, state}
    rescue
      error ->
        Logger.warning("Failed to save default subscriptions: #{inspect(error)}")
        {:reply, {:error, error}, state}
    catch
      :exit, reason ->
        Logger.warning("Failed to save default subscriptions (exit): #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(msg, _from, state) do
    Logger.warning("Leader received unexpected CALL: #{inspect(msg)}")
    {:reply, :ok, state}
  end

  ############# PLUMBING #############
  #
  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("#{Themes.cluster(self(), "terminating with reason: #{inspect(reason)}")}")
    :ok
  end
  @impl true
  def init(config) do
    # Set trap_exit early to handle crashes properly
    Process.flag(:trap_exit, true)
    
    # Extract store_id and calculate the store-specific name
    store_id = StoreNaming.extract_store_id(config)
    expected_name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    # Log startup with process info
    IO.puts("#{Themes.leader_worker(self(), "is UP!")}") 
    Logger.info("LeaderWorker started successfully with PID #{inspect(self())} and name #{inspect(expected_name)}")
    
    # Verify we're properly registered with the store-specific name
    case Process.whereis(expected_name) do
      pid when pid == self() ->
        Logger.info("LeaderWorker registration confirmed: #{inspect(expected_name)} -> #{inspect(self())}")
      other_pid ->
        Logger.warning("LeaderWorker registration issue: expected #{inspect(self())}, got #{inspect(other_pid)}")
    end
    
    {:ok, config}
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
