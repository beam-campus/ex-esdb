defmodule ExESDB.StoreWorker do
  @moduledoc """
    A GenServer wrapper around :khepri to act as a distributed event store.
    Inspired by EventStoreDB's API.
  """
  use GenServer

  require Logger

  alias ExESDB.Themes, as: Themes

  defp start_khepri(opts) do
    store = opts[:store_id]
    timeout = opts[:timeout]
    data_dir = opts[:data_dir]
    :khepri.start(data_dir, store, timeout)
  end

  # Client API
  @doc """
  Get the current state of the store.
  ## Returns

      - `{:ok, state}`  if successful.
      - `{:error, reason}` if unsuccessful.

  """
  def get_state,
    do:
      GenServer.call(
        __MODULE__,
        {:get_state}
      )

  ## CALLBACKS
  @impl true
  def handle_call({:get_state}, _from, state) do
    {:reply, {:ok, state}, state}
  end

  #### PLUMBING
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 10_000,
      type: :worker
    }
  end

  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  # Server Callbacks
  @impl true
  def init(opts) do
    IO.puts(Themes.store(self(), "is UP."))
    Process.flag(:trap_exit, true)

    case start_khepri(opts) do
      {:ok, store} ->
        Logger.debug("Started store: #{inspect(store)}")
        {:ok, [config: opts, store: store]}

      reason ->
        Logger.error("Failed to start khepri. reason: #{inspect(reason)}")

        {:error, [config: opts, store: nil]}
    end
  end

  @impl true
  def terminate(reason, [config: opts, store: store]) do
    IO.puts(Themes.store(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}"))
    
    # Stop Khepri store gracefully if it was started
    if store do
      store_id = opts[:store_id]
      Logger.info("Stopping Khepri store: #{inspect(store_id)}")
      
      case :khepri.stop(store_id) do
        :ok ->
          Logger.info("Successfully stopped Khepri store: #{inspect(store_id)}")
        {:error, reason} ->
          Logger.warning("Failed to stop Khepri store #{inspect(store_id)}: #{inspect(reason)}")
        other ->
          Logger.warning("Unexpected response stopping Khepri store #{inspect(store_id)}: #{inspect(other)}")
      end
    end
    
    :ok
  end

  def terminate(reason, _state) do
    IO.puts(Themes.store(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}"))
    :ok
  end
end
