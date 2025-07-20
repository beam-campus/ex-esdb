defmodule ExESDB.SubscriptionsWriter do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  use GenServer

  require Logger
  alias ExESDB.PersistenceWorker, as: PersistenceWorker
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  def put_subscription(
        store,
        type,
        selector,
        subscription_name \\ "transient",
        start_from \\ 0,
        subscriber \\ nil
      ) do
    name = StoreNaming.genserver_name(__MODULE__, store)

    GenServer.cast(
      name,
      {:put_subscription, store, type, selector, subscription_name, start_from, subscriber}
    )
  end

  def delete_subscription(store, type, selector, subscription_name) do
    name = StoreNaming.genserver_name(__MODULE__, store)

    GenServer.cast(
      name,
      {:delete_subscription, store, type, selector, subscription_name}
    )
  end

  ############ CALLBACKS ############
  @impl true
  def handle_cast({:delete_subscription, store, type, selector, subscription_name}, state) do
    key =
      :subscriptions_store.key({type, selector, subscription_name})

    if store
       |> :khepri.exists!([:subscriptions, key]) do
      store
      |> :khepri.delete!([:subscriptions, key])

      # Request asynchronous persistence
      spawn(fn -> PersistenceWorker.request_persistence(store) end)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:put_subscription, store, type, selector, subscription_name, start_from, subscriber},
        state
      ) do
    subscription =
      %{
        selector: selector,
        type: type,
        subscription_name: subscription_name,
        start_from: start_from,
        subscriber: subscriber
      }

    if :subscriptions_store.exists(store, subscription) do
      store
      |> :subscriptions_store.update_subscription(subscription)
    else
      store
      |> :subscriptions_store.put_subscription(subscription)
    end

    # Request asynchronous persistence
    spawn(fn -> PersistenceWorker.request_persistence(store) end)

    {:noreply, state}
  end

  ######## PLUMBING ############
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    IO.puts(Themes.subscriptions_writer(self(), "is UP."))
    {:ok, opts}
  end

  @impl true
  def terminate(reason, _state) do
    IO.puts(
      Themes.subscriptions_writer(
        self(),
        "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}"
      )
    )

    :ok
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
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
