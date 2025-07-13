defmodule ExESDB.StoreManager do
  @moduledoc """
  Manages multiple event stores dynamically within a single ExESDB cluster.
  
  This module provides the API for creating, starting, stopping, and managing
  multiple stores at runtime. Each store has its own unique identifier and
  operates independently within the shared cluster infrastructure.
  """
  use GenServer

  require Logger
  alias BCUtils.ColorFuncs, as: CF

  @type store_id :: atom()
  @type store_config :: keyword()
  @type store_status :: :starting | :running | :stopping | :stopped | :error

  defstruct stores: %{}, default_config: []

  ## Client API

  @doc """
  Creates and starts a new store with the given store_id and configuration.
  
  ## Parameters
  - `store_id`: Unique identifier for the store (atom)
  - `config`: Optional configuration overrides (keyword list)
  
  ## Returns
  - `{:ok, store_id}` if successful
  - `{:error, reason}` if failed
  """
  @spec create_store(store_id(), store_config()) :: {:ok, store_id()} | {:error, term()}
  def create_store(store_id, config \\ []) do
    GenServer.call(__MODULE__, {:create_store, store_id, config})
  end

  @doc """
  Stops and removes a store from the manager.
  
  ## Parameters
  - `store_id`: The store identifier to remove
  
  ## Returns
  - `:ok` if successful
  - `{:error, reason}` if failed
  """
  @spec remove_store(store_id()) :: :ok | {:error, term()}
  def remove_store(store_id) do
    GenServer.call(__MODULE__, {:remove_store, store_id})
  end

  @doc """
  Lists all currently managed stores and their status.
  
  ## Returns
  - `%{store_id => %{status: store_status, config: store_config}}`
  """
  @spec list_stores() :: map()
  def list_stores do
    GenServer.call(__MODULE__, :list_stores)
  end

  @doc """
  Gets the status of a specific store.
  
  ## Parameters
  - `store_id`: The store identifier
  
  ## Returns
  - `{:ok, store_status}` if store exists
  - `{:error, :not_found}` if store doesn't exist
  """
  @spec get_store_status(store_id()) :: {:ok, store_status()} | {:error, :not_found}
  def get_store_status(store_id) do
    GenServer.call(__MODULE__, {:get_store_status, store_id})
  end

  @doc """
  Gets the configuration for a specific store.
  
  ## Parameters
  - `store_id`: The store identifier
  
  ## Returns
  - `{:ok, store_config}` if store exists
  - `{:error, :not_found}` if store doesn't exist
  """
  @spec get_store_config(store_id()) :: {:ok, store_config()} | {:error, :not_found}
  def get_store_config(store_id) do
    GenServer.call(__MODULE__, {:get_store_config, store_id})
  end

  ## GenServer Implementation

  def start_link(default_config) do
    GenServer.start_link(__MODULE__, default_config, name: __MODULE__)
  end

  def child_spec(default_config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [default_config]},
      restart: :permanent,
      shutdown: 10_000,
      type: :worker
    }
  end

  @impl true
  def init(default_config) do
    Logger.info("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] StoreManager is starting",
      module: __MODULE__,
      component: :store,
      pid: self()
    )
    
    # Initialize with any pre-configured stores
    initial_stores = initialize_default_stores(default_config)
    
    state = %__MODULE__{
      stores: initial_stores,
      default_config: default_config
    }
    
    Logger.info("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] StoreManager is UP with #{map_size(initial_stores)} stores",
      module: __MODULE__,
      component: :store,
      pid: self()
    )
    {:ok, state}
  end

  @impl true
  def handle_call({:create_store, store_id, config}, _from, state) do
    case Map.has_key?(state.stores, store_id) do
      true ->
        {:reply, {:error, :already_exists}, state}
      
      false ->
        merged_config = Keyword.merge(state.default_config, config)
        store_config = Keyword.put(merged_config, :store_id, store_id)
        
        case start_store(store_id, store_config) do
          {:ok, _pid} ->
            new_stores = Map.put(state.stores, store_id, %{
              status: :running,
              config: store_config,
              pid: nil
            })
            
            new_state = %{state | stores: new_stores}
            Logger.info("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Created new store: #{store_id}",
              module: __MODULE__,
              component: :store,
              pid: self(),
              store_id: store_id
            )
            {:reply, {:ok, store_id}, new_state}
          
          {:error, reason} ->
            Logger.error("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Failed to create store #{store_id}: #{inspect(reason)}",
              module: __MODULE__,
              component: :store,
              pid: self(),
              store_id: store_id,
              reason: reason
            )
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:remove_store, store_id}, _from, state) do
    case Map.get(state.stores, store_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      _store_info ->
        case stop_store(store_id) do
          :ok ->
            new_stores = Map.delete(state.stores, store_id)
            new_state = %{state | stores: new_stores}
            Logger.info("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Removed store: #{store_id}",
              module: __MODULE__,
              component: :store,
              pid: self(),
              store_id: store_id
            )
            {:reply, :ok, new_state}
          
          {:error, reason} ->
            Logger.error("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Failed to remove store #{store_id}: #{inspect(reason)}",
              module: __MODULE__,
              component: :store,
              pid: self(),
              store_id: store_id,
              reason: reason
            )
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_stores, _from, state) do
    stores_info = Map.new(state.stores, fn {store_id, info} ->
      {store_id, %{status: info.status, config: info.config}}
    end)
    {:reply, stores_info, state}
  end

  @impl true
  def handle_call({:get_store_status, store_id}, _from, state) do
    case Map.get(state.stores, store_id) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, info.status}, state}
    end
  end

  @impl true
  def handle_call({:get_store_config, store_id}, _from, state) do
    case Map.get(state.stores, store_id) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, info.config}, state}
    end
  end

  ## Private Functions

  defp initialize_default_stores(default_config) do
    # Start with the primary store if configured
    store_id = Keyword.get(default_config, :store_id, :ex_esdb_store)
    
    case start_store(store_id, default_config) do
      {:ok, _pid} ->
        %{store_id => %{status: :running, config: default_config, pid: nil}}
      
      {:error, reason} ->
        Logger.error("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Failed to start default store #{store_id}: #{inspect(reason)}",
          module: __MODULE__,
          component: :store,
          pid: self(),
          store_id: store_id,
          reason: reason
        )
        %{}
    end
  end

  defp start_store(store_id, config) do
    # Create a unique data directory for this store
    base_data_dir = Keyword.get(config, :data_dir, "/data")
    store_data_dir = Path.join(base_data_dir, to_string(store_id))
    
    # Ensure the directory exists
    File.mkdir_p!(store_data_dir)
    
    # Update config with store-specific data directory
    store_config = Keyword.put(config, :data_dir, store_data_dir)
    
    # Start the Khepri store directly
    start_khepri_store(store_config)
  end

  defp start_khepri_store(config) do
    store_id = Keyword.get(config, :store_id)
    timeout = Keyword.get(config, :timeout, 10_000)
    data_dir = Keyword.get(config, :data_dir)
    
    case :khepri.start(data_dir, store_id, timeout) do
      {:ok, store} ->
        Logger.debug("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Started Khepri store: #{inspect(store)}",
          module: __MODULE__,
          component: :store,
          pid: self(),
          khepri_store: store
        )
        {:ok, store}
      
      {:error, {:already_started, store}} ->
        Logger.debug("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Khepri store already started: #{inspect(store)}",
          module: __MODULE__,
          component: :store,
          pid: self(),
          khepri_store: store
        )
        {:ok, store}
      
      {:error, reason} ->
        Logger.error("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Failed to start Khepri store #{store_id}: #{inspect(reason)}",
          module: __MODULE__,
          component: :store,
          pid: self(),
          store_id: store_id,
          reason: reason
        )
        {:error, reason}
    end
  end

  defp stop_store(store_id) do
    case :khepri.stop(store_id) do
      :ok ->
        Logger.debug("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Stopped Khepri store: #{store_id}",
          module: __MODULE__,
          component: :store,
          pid: self(),
          store_id: store_id
        )
        :ok
      
      {:error, reason} ->
        Logger.error("STORE [#{CF.black_on_green()}#{inspect(self())}#{CF.reset()}] Failed to stop Khepri store #{store_id}: #{inspect(reason)}",
          module: __MODULE__,
          component: :store,
          pid: self(),
          store_id: store_id,
          reason: reason
        )
        {:error, reason}
    end
  end
end
