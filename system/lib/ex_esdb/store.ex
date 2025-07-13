defmodule ExESDB.Store do
  @moduledoc """
    A GenServer wrapper around :khepri to act as a distributed event store.
    Inspired by EventStoreDB's API.
  """
  use GenServer

  require Logger

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
  def get_state(),
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
    Logger.info("Store #{inspect(self())} is UP.")
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
end
