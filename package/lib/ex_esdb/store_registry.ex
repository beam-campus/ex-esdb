defmodule ExESDB.StoreRegistry do
  @moduledoc false
  use GenServer

  alias ExESDB.Themes, as: Themes
  require Logger
  alias UUIDv7
  alias ExESDB.StoreNaming

  def registry_name, do: {:store_registry, :erlang.phash2(UUIDv7.generate())}

  def all_registries do
    Swarm.registered()
    |> Enum.filter(fn {name, _pid} -> match?({:store_registry, _}, name) end)
    |> Enum.map(fn {_, pid} -> pid end)
  end

  def other_registries do
    current = self()

    all_registries()
    |> Enum.reject(fn pid -> pid == current end)
  end

  def random_registry, do: all_registries() |> Enum.random()

  ####################### API #######################
  def list_stores,
    do:
      GenServer.call(
        random_registry(),
        {:list_stores}
      )

  @doc """
  Queries stores by database type (e.g., :single, :cluster).

  This demonstrates the value of having richer store information
  beyond just store_id.
  """
  def list_stores_by_db_type(db_type) do
    case list_stores() do
      {:ok, stores} ->
        filtered_stores =
          stores
          |> Enum.filter(fn %{store: store_config} ->
            store_config[:db_type] == db_type
          end)

        {:ok, filtered_stores}

      error ->
        error
    end
  end

  @doc """
  Queries stores by timeout configuration.

  Useful for finding stores with specific performance characteristics.
  """
  def list_stores_by_timeout(timeout) do
    case list_stores() do
      {:ok, stores} ->
        filtered_stores =
          stores
          |> Enum.filter(fn %{store: store_config} ->
            store_config[:timeout] == timeout
          end)

        {:ok, filtered_stores}

      error ->
        error
    end
  end

  @doc """
  Gets detailed store information for a specific store_id.

  Returns the full store configuration including all operational parameters.
  """
  def get_store_info(store_id) do
    case list_stores() do
      {:ok, stores} ->
        case Enum.find(stores, fn %{store: %{store_id: id}} -> id == store_id end) do
          nil -> {:error, :not_found}
          store -> {:ok, store}
        end

      error ->
        error
    end
  end

  def sync_stores do
    other_registries()
    |> Enum.map(&safe_list_stores/1)
    |> Enum.reduce([], fn
      {:ok, stores}, acc -> stores ++ acc
      _, acc -> acc
    end)
    |> Enum.uniq_by(fn %{store: %{store_id: id}, node: node} -> {id, node} end)
  end

  def announce(store, node) do
    other_registries()
    |> Enum.map(fn pid -> safe_announce_store(pid, store, node) end)
    |> Enum.reduce([], fn
      {:ok, stores}, acc -> stores ++ acc
      _, acc -> acc
    end)
    |> Enum.uniq_by(fn %{store: %{store_id: id}, node: node} -> {id, node} end)
  end

  def unregister(store, node) do
    other_registries()
    |> Enum.each(fn pid ->
      GenServer.cast(
        pid,
        {:unregister_store_for_node, store, node}
      )
    end)
  end

  defp remove_store_for_node(stores, gone_id, gone_node) do
    stores
    |> Enum.filter(fn %{store: %{store_id: id}, node: node} ->
      id != gone_id || node != gone_node
    end)
  end

  defp maybe_add_store_for_node(stores, %{store_id: maybe_store_id} = maybe_store, maybe_node) do
    case stores
         |> Enum.find(fn %{store: %{store_id: id}, node: node} ->
           id == maybe_store_id && node == maybe_node
         end) do
      nil ->
        IO.puts(
          Themes.store_registry(
            self(),
            "✍️ Registering store [#{maybe_store_id}] on node [#{inspect(maybe_node)}]"
          )
        )

        store_with_node = %{store: maybe_store, node: maybe_node}

        [store_with_node | stores]

      %{store: %{store_id: store_id}, node: node} ->
        IO.puts(
          Themes.store_registry(
            self(),
            "⚠️ Store [#{store_id}] on node [#{inspect(node)}] already registered"
          )
        )

        stores
    end
  end

  ############ CALLBACKS ############
  @impl true
  def handle_call(
        {:announce_store_for_node, store_config, node},
        _from,
        %{stores: stores} = state
      ) do
    registered_stores =
      stores
      |> maybe_add_store_for_node(store_config, node)

    state = %{state | stores: registered_stores}

    # Respond with current list of stores
    {:reply, {:ok, state.stores}, state}
  end

  @impl true
  def handle_call({:list_stores}, _from, state) do
    {:reply, {:ok, state.stores}, state}
  end

  @impl true
  def handle_cast(
        {:unregister_store_for_node, %{store_id: gone_id} = _store_config, gone_node},
        %{stores: stores} = state
      ) do
    IO.puts(
      Themes.store_registry(
        self(),
        "👋 Unregistering store [#{gone_id}] on node [#{inspect(gone_node)}]"
      )
    )

    filtered_stores =
      stores
      |> remove_store_for_node(gone_id, gone_node)

    state = %{state | stores: filtered_stores}

    {:noreply, state}
  end

  @impl true
  def handle_info({:announce, %{store_id: store_id} = store_config}, state) do
    # Announce to other registries and collect their stores
    collected_stores = announce(store_config, node())

    # Merge with collected stores (avoiding duplicates with existing stores)
    current_stores = state.stores || []

    all_stores =
      (current_stores ++ collected_stores)
      |> Enum.uniq_by(fn %{store: %{store_id: id}, node: n} -> {id, n} end)

    IO.puts(
      Themes.store_registry(
        self(),
        "📢 Announced store #{store_id} from node #{node()} 📢"
      )
    )

    new_state = %{state | stores: all_stores}
    {:noreply, new_state}
  end

  ####################### PLUMBING #######################
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Swarm.register_name(registry_name(), self())
    IO.puts(Themes.store_registry(self(), "is UP"))

    # Initialize state as a map with stores
    init_state = %{
      config: opts,
      stores: []
    }

    # Add our own store to initial state if store_id is provided
    state =
      if store_id = Keyword.get(opts, :store_id) do
        store_config = build_store_config(opts)
        local_store = %{store: store_config, node: node()}

        IO.puts(
          Themes.store_registry(
            self(),
            "🏪 Added own store [#{inspect(store_id)}] with full config to registry."
          )
        )

        # Schedule announcement after a short delay to avoid blocking init
        Process.send_after(self(), {:announce, store_config}, 500)
        %{init_state | stores: [local_store]}
      end

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

  @impl true
  def terminate(reason, state) do
    IO.puts(
      Themes.store_registry(self(), "⚠️ Terminating on #{node()} with reason: #{inspect(reason)}")
    )

    # Unregister this store from all other registries before shutting down
    if store_id = Keyword.get(state.config, :store_id) do
      store_config = build_store_config(state.config)
      unregister(store_config, node())

      IO.puts(
        Themes.store_registry(
          self(),
          "👋 Unregistered store [#{inspect(store_id)}] from #{length(other_registries())} other registries."
        )
      )
    end

    :ok
  end

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end

  ####################### HELPERS #######################

  @doc """
  Transforms a keyword list configuration into a rich store configuration map.

  This function extracts all relevant store configuration options and creates
  a structured map that can be used for store registration and querying.
  """
  def build_store_config(opts) when is_list(opts) do
    %{
      store_id: Keyword.get(opts, :store_id),
      data_dir: Keyword.get(opts, :data_dir),
      timeout: Keyword.get(opts, :timeout),
      db_type: Keyword.get(opts, :db_type),
      pub_sub: Keyword.get(opts, :pub_sub),
      reader_idle_ms: Keyword.get(opts, :reader_idle_ms),
      writer_idle_ms: Keyword.get(opts, :writer_idle_ms),
      store_description: Keyword.get(opts, :store_description),
      # Operational metadata
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      version: Keyword.get(opts, :version, 1),
      status: Keyword.get(opts, :status, :active),
      # Resource management
      priority: Keyword.get(opts, :priority, :normal),
      auto_start: Keyword.get(opts, :auto_start, true),
      # Administrative
      tags: Keyword.get(opts, :store_tags, []),
      environment: Keyword.get(opts, :environment)
    }
  end

  def build_store_config(opts), do: opts

  ## Helper Functions for Safe GenServer Calls

  defp safe_list_stores(registry) do
    case GenServer.call(registry, {:list_stores}, 5000) do
      result -> result
    end
  catch
    :exit, _reason -> {:ok, []}
    _other -> {:ok, []}
  end

  defp safe_announce_store(pid, store, node) do
    case GenServer.call(pid, {:announce_store_for_node, store, node}, 5000) do
      result -> result
    end
  catch
    :exit, _reason -> {:ok, []}
    _other -> {:ok, []}
  end
end
