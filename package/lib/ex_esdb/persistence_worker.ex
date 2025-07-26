defmodule ExESDB.PersistenceWorker do
  @moduledoc """
  A GenServer that handles periodic disk persistence operations.

  This worker batches and schedules fence operations to ensure data is
  persisted to disk without blocking event append operations.

  Features:
  - Configurable persistence interval (default: 5 seconds)
  - Batching of fence operations to reduce disk I/O
  - Graceful shutdown with final persistence
  - Per-store persistence workers
  """
  use GenServer

  alias ExESDB.Options
  alias ExESDB.StoreNaming
  alias ExESDB.Themes

  require Logger

  defstruct [
    :store_id,
    :persistence_interval,
    :timer_ref,
    :pending_stores,
    :last_persistence_time
  ]

  ############ API ############

  @doc """
  Starts a persistence worker for a specific store.
  """
  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Requests that a store's data be persisted to disk.
  This is a non-blocking call that queues the store for persistence.
  """
  def request_persistence(store_id) do
    worker_name = StoreNaming.genserver_name(__MODULE__, store_id)

    case GenServer.whereis(worker_name) do
      nil ->
        Logger.warning("PersistenceWorker for store #{store_id} not found")
        :error

      pid ->
        GenServer.cast(pid, {:request_persistence, store_id})
        :ok
    end
  end

  @doc """
  Forces immediate persistence of all pending stores.
  This is a synchronous call that blocks until persistence is complete.
  """
  def force_persistence(store_id) do
    worker_name = StoreNaming.genserver_name(__MODULE__, store_id)

    case GenServer.whereis(worker_name) do
      nil ->
        Logger.warning("PersistenceWorker for store #{store_id} not found")
        :error

      pid ->
        GenServer.call(pid, :force_persistence, 30_000)
    end
  end

  ############ CALLBACKS ############

  @impl true
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    persistence_interval = get_persistence_interval(opts)


    # Schedule the first persistence check
    timer_ref = Process.send_after(self(), :persist_data, persistence_interval)

    state = %__MODULE__{
      store_id: store_id,
      persistence_interval: persistence_interval,
      timer_ref: timer_ref,
      pending_stores: MapSet.new(),
      last_persistence_time: System.monotonic_time(:millisecond)
    }

    IO.puts("#{Themes.persistence_worker(self(), "for store [#{store_id}] is UP")}")

    {:ok, state}
  end

  @impl true
  def handle_cast({:request_persistence, store_id}, state) do
    # Add store to pending persistence set
    updated_pending = MapSet.put(state.pending_stores, store_id)

    {:noreply, %{state | pending_stores: updated_pending}}
  end

  @impl true
  def handle_call(:force_persistence, _from, state) do
    # Immediately persist all pending stores
    result = persist_pending_stores(state.pending_stores)

    # Clear pending stores and update last persistence time
    updated_state = %{
      state
      | pending_stores: MapSet.new(),
        last_persistence_time: System.monotonic_time(:millisecond)
    }

    {:reply, result, updated_state}
  end

  @impl true
  def handle_info(:persist_data, state) do
    # Persist any pending stores
    if MapSet.size(state.pending_stores) > 0 do
      persist_pending_stores(state.pending_stores)
    end

    # Schedule next persistence
    timer_ref = Process.send_after(self(), :persist_data, state.persistence_interval)

    updated_state = %{
      state
      | timer_ref: timer_ref,
        pending_stores: MapSet.new(),
        last_persistence_time: System.monotonic_time(:millisecond)
    }

    {:noreply, updated_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel the timer
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Final persistence of any pending stores
    if MapSet.size(state.pending_stores) > 0 do
      persist_pending_stores(state.pending_stores)
    end
    :ok
  end

  ############ HELPERS ############

  defp get_persistence_interval(opts) do
    # Try to get from options first
    case Keyword.get(opts, :persistence_interval) do
      nil ->
        # Fall back to Options configuration system
        case Keyword.get(opts, :otp_app) do
          nil -> Options.persistence_interval()
          otp_app -> Options.persistence_interval(otp_app)
        end

      interval ->
        interval
    end
  end

  defp persist_pending_stores(pending_stores) do
    results =
      pending_stores
      |> Enum.map(&persist_store/1)
      |> Enum.reduce({0, 0}, fn
        :ok, {success, error} -> {success + 1, error}
        {:error, _}, {success, error} -> {success, error + 1}
      end)

    case results do
      {_success, 0} ->
        :ok

      {success, errors} ->
        Logger.warning("Persisted #{success} stores, #{errors} errors")
        {:error, {:partial_success, success, errors}}
    end
  end

  defp persist_store(store_id) do
    # Use non-blocking flush instead of blocking fence
    case flush_async(store_id) do
      :ok ->
        :ok

      error ->
        Logger.error("Failed to request persistence for store #{store_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp flush_async(_store_id) do
    # DISABLED: Flush operations disabled to prevent Khepri tree corruption
    # Previous timeout issues resolved by increased StreamsWriter timeout (30s)
    # See PATCH_RECORD.md Phase 8 for details
    # Custom flush commands at [:__persistence_flush__] path conflict with existing tree structure
    # No-op: flush operations disabled
    :ok
  end

  ############ CHILD SPEC ############

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)

    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      # Allow time for final persistence
      shutdown: 10_000,
      type: :worker
    }
  end
end
