defmodule ExESDB.StoreWorker do
  @moduledoc """
    A GenServer wrapper around :khepri to act as a distributed event store.
    Inspired by EventStoreDB's API.
  """
  use GenServer

  require Logger

  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming
  alias ExESDB.PubSubIntegration

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
  def get_state(store_id \\ nil),
    do:
      GenServer.call(
        StoreNaming.genserver_name(__MODULE__, store_id),
        {:get_state}
      )

  ## CALLBACKS
  @impl true
  def handle_call({:get_state}, _from, state) do
    {:reply, {:ok, state}, state}
  end

  #### PLUMBING
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

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    IO.puts(Themes.store(self(), "is UP."))
    Process.flag(:trap_exit, true)
    
    store_id = opts[:store_id] || "default"

    case start_khepri(opts) do
      {:ok, store} ->
        Logger.debug("Started store: #{inspect(store)}")
        
        # Broadcast store startup event
        PubSubIntegration.broadcast_system_config(:store, %{
          store_id: store_id,
          status: :started,
          node: Node.self(),
          backend: :khepri
        })
        
        PubSubIntegration.broadcast_health_update(
          :store_worker, 
          :healthy, 
          %{store_id: store_id, backend: :khepri}
        )
        
        {:ok, [config: opts, store: store]}

      reason ->
        Logger.error("Failed to start khepri. reason: #{inspect(reason)}")
        
        # Broadcast store failure event
        PubSubIntegration.broadcast_alert(
          :store_failure, 
          :critical, 
          "Failed to start store #{store_id}", 
          %{store_id: store_id, reason: reason, backend: :khepri}
        )
        
        PubSubIntegration.broadcast_health_update(
          :store_worker, 
          :unhealthy, 
          %{store_id: store_id, error: reason, backend: :khepri}
        )

        {:error, [config: opts, store: nil]}
    end
  end

  @impl true
  def terminate(reason, [config: opts, store: store]) do
    store_id = opts[:store_id] || "default"
    IO.puts(Themes.store(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}"))
    
    # Broadcast store stopping event
    PubSubIntegration.broadcast_system_config(:store, %{
      store_id: store_id,
      status: :stopping,
      node: Node.self(),
      reason: reason,
      backend: :khepri
    })
    
    # Stop Khepri store gracefully if it was started
    if store do
      Logger.info("Stopping Khepri store: #{inspect(store_id)}")
      
      case :khepri.stop(store_id) do
        :ok ->
          Logger.info("Successfully stopped Khepri store: #{inspect(store_id)}")
          
          # Broadcast successful shutdown
          PubSubIntegration.broadcast_system_config(:store, %{
            store_id: store_id,
            status: :stopped,
            node: Node.self(),
            backend: :khepri
          })
          
        {:error, reason} ->
          Logger.warning("Failed to stop Khepri store #{inspect(store_id)}: #{inspect(reason)}")
          
          # Broadcast shutdown failure
          PubSubIntegration.broadcast_alert(
            :store_failure, 
            :warning, 
            "Failed to stop store #{store_id}", 
            %{store_id: store_id, reason: reason, backend: :khepri}
          )
          
        other ->
          Logger.warning("Unexpected response stopping Khepri store #{inspect(store_id)}: #{inspect(other)}")
          
          PubSubIntegration.broadcast_alert(
            :store_failure, 
            :warning, 
            "Unexpected response stopping store #{store_id}", 
            %{store_id: store_id, response: other, backend: :khepri}
          )
      end
    end
    
    :ok
  end

  def terminate(reason, _state) do
    IO.puts(Themes.store(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}"))
    :ok
  end
end
