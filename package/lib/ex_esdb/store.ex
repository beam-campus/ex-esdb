defmodule ExESDB.Store do
  @moduledoc """
    A GenServer wrapper around :khepri to act as a distributed event store.
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
      
  @doc """
  Get the store-specific GenServer name.
  
  This function returns the name used to register this store GenServer,
  allowing multiple stores to run on the same node.
  
  ## Parameters
  
  * `store_id` - The store identifier (optional)
  
  ## Examples
  
      iex> ExESDB.Store.store_name("my_store")
      {:ex_esdb_store, "my_store"}
      
      iex> ExESDB.Store.store_name(nil)
      ExESDB.Store
  """
  def store_name(store_id), do: StoreNaming.genserver_name(__MODULE__, store_id)

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
    IO.puts("#{Themes.store(self(), "is UP.")}")
    Process.flag(:trap_exit, true)
    
    store_id = StoreNaming.extract_store_id(opts)
    
    case start_khepri(opts) do
      {:ok, store} ->
        # Broadcast successful store startup
        PubSubIntegration.broadcast_lifecycle_event(
          :store_started,
          store_id,
          %{
            store_id: store_id,
            data_dir: opts[:data_dir],
            timeout: opts[:timeout]
          }
        )
        
        # Broadcast store health as healthy
        PubSubIntegration.broadcast_store_health(
          store_id,
          :khepri_store,
          :healthy,
          %{
            event: :started,
            node: Node.self()
          }
        )
        
        {:ok, [config: opts, store: store]}

      reason ->
        Logger.error("Failed to start Khepri store. Reason: #{inspect(reason)}")
        
        # Broadcast store failure
        PubSubIntegration.broadcast_alert(
          :store_startup_failed,
          :critical,
          "Failed to start Khepri store #{store_id}",
          %{
            store_id: store_id,
            reason: reason,
            node: Node.self()
          }
        )
        
        # Broadcast store health as unhealthy
        PubSubIntegration.broadcast_store_health(
          store_id,
          :khepri_store,
          :unhealthy,
          %{
            event: :startup_failed,
            reason: reason,
            node: Node.self()
          }
        )
        
        {:error, [config: opts, store: nil]}
    end
  end

  @impl true
  def terminate(reason, [config: opts, store: store]) do
    IO.puts("#{Themes.store(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}")}")
    
    store_id = StoreNaming.extract_store_id(opts)
    
    # Broadcast store shutdown event
    PubSubIntegration.broadcast_lifecycle_event(
      :store_stopping,
      store_id,
      %{
        store_id: store_id,
        reason: reason,
        node: Node.self()
      }
    )
    
    # Stop Khepri store gracefully if it was started
    if store do
      case :khepri.stop(store_id) do
        :ok -> 
          # Broadcast successful shutdown
          PubSubIntegration.broadcast_lifecycle_event(
            :store_stopped,
            store_id,
            %{
              store_id: store_id,
              reason: reason,
              shutdown_success: true,
              node: Node.self()
            }
          )
          
          # Broadcast store health as unhealthy (stopped)
          PubSubIntegration.broadcast_store_health(
            store_id,
            :khepri_store,
            :unhealthy,
            %{
              event: :stopped,
              reason: reason,
              node: Node.self()
            }
          )
          
          :ok
          
        {:error, stop_reason} ->
          Logger.warning("Failed to stop Khepri store #{inspect(store_id)}: #{inspect(stop_reason)}")
          
          # Broadcast failed shutdown
          PubSubIntegration.broadcast_alert(
            :store_shutdown_failed,
            :warning,
            "Failed to cleanly stop Khepri store #{store_id}",
            %{
              store_id: store_id,
              reason: stop_reason,
              node: Node.self()
            }
          )
          
        other ->
          Logger.warning("Unexpected response stopping Khepri store #{inspect(store_id)}: #{inspect(other)}")
      end
    end
    
    :ok
  end

  def terminate(reason, _state) do
    IO.puts("#{Themes.store(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}")}")
    
    # Broadcast generic termination for stores without proper state
    PubSubIntegration.broadcast_lifecycle_event(
      :store_terminated,
      :unknown_store,
      %{
        reason: reason,
        node: Node.self()
      }
    )
    
    :ok
  end
end
