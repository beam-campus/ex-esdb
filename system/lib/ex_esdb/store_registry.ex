defmodule ExESDB.StoreRegistry do
  @moduledoc false
  use GenServer

  alias ExESDB.Themes, as: Themes
  require Logger
  alias UUIDv7

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

  def sync_stores do
    other_registries()
    |> Enum.map(fn registry ->
      try do
        GenServer.call(registry, {:list_stores}, 5000)
      rescue
        _ -> {:ok, []}
      catch
        :exit, _ -> {:ok, []}
      end
    end)
    |> Enum.reduce([], fn
      {:ok, stores}, acc -> stores ++ acc
      _, acc -> acc
    end)
    |> Enum.uniq_by(fn %{store: %{store_id: id}, node: node} -> {id, node} end)
  end

  def announce(store, node) do
    other_registries()
    |> Enum.map(fn pid ->
      try do
        # Send announce to all existing registries and collect their stores
        GenServer.call(
          pid,
          {:announce_store_for_node, store, node},
          5000
        )
      rescue
        _ -> {:ok, []}
      catch
        :exit, _ -> {:ok, []}
      end
    end)
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
            "✍️ Registering store [#{inspect(maybe_store)}] on node [#{inspect(maybe_node)}]"
          )
        )

        store_with_node = %{store: maybe_store, node: maybe_node}

        [store_with_node | stores]

      %{store: store, node: node} ->
        Logger.warning(
          Themes.store_registry(
            self(),
            "Store [#{inspect(store)}] on node [#{inspect(node)}] already registered"
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
        "👋 Unregistering store [#{inspect(gone_id)}] on node [#{inspect(gone_node)}]"
      )
    )

    filtered_stores =
      stores
      |> remove_store_for_node(gone_id, gone_node)

    state = %{state | stores: filtered_stores}

    {:noreply, state}
  end

  @impl true
  def handle_info({:announce, store_config}, state) do
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
        "📢 Announced store and synced with #{length(collected_stores)} stores from #{length(other_registries())} registries"
      )
    )

    new_state = %{state | stores: all_stores}
    {:noreply, new_state}
  end

  ####################### PLUMBING #######################
  @impl true
  def init(opts) do
    Swarm.register_name(registry_name(), self())
    IO.puts(Themes.store_registry(self(), "is UP"))

    # Initialize state as a map with stores
    state = %{
      config: opts,
      stores: []
    }

    # Add our own store to initial state if store_id is provided
    if store_id = Keyword.get(opts, :store_id) do
      store_config = %{store_id: store_id}
      local_store = %{store: store_config, node: node()}
      state = %{state | stores: [local_store]}

      IO.puts(
        Themes.store_registry(
          self(),
          "🏪 Added own store [#{inspect(store_id)}] to registry"
        )
      )

      # Schedule announcement after a short delay to avoid blocking init
      Process.send_after(self(), {:announce, store_config}, 500)
    end

    {:ok, state}
  end

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: __MODULE__
    )
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning(Themes.store_registry(self(), "terminating with reason: #{inspect(reason)}"))

    # Unregister this store from all other registries before shutting down
    if store_id = Keyword.get(state.config, :store_id) do
      store_config = %{store_id: store_id}
      unregister(store_config, node())

      IO.puts(
        Themes.store_registry(
          self(),
          "👋 Unregistered store [#{inspect(store_id)}] from #{length(other_registries())} other registries"
        )
      )
    end

    :ok
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end
end
