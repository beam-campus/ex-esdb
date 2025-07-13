defmodule ExESDB.SubscriptionsWriter do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  use GenServer

  require Logger

  def put_subscription(
        store,
        type,
        selector,
        subscription_name \\ "transient",
        start_from \\ 0,
        subscriber \\ nil
      ),
      do:
        GenServer.cast(
          __MODULE__,
          {:put_subscription, store, type, selector, subscription_name, start_from, subscriber}
        )

  def delete_subscription(store, type, selector, subscription_name),
    do:
      GenServer.cast(
        __MODULE__,
        {:delete_subscription, store, type, selector, subscription_name}
      )

  ############ CALLBACKS ############
  @impl true
  def handle_cast({:delete_subscription, store, type, selector, subscription_name}, state) do
    key =
      :subscriptions_store.key({type, selector, subscription_name})

    if store
       |> :khepri.exists!([:subscriptions, key]) do
      store
      |> :khepri.delete!([:subscriptions, key])
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

    {:noreply, state}
  end

  ######## PLUMBING ############
  @impl true
  def init(opts) do
    Logger.info("SubscriptionsWriter #{inspect(self())} is UP.")
    {:ok, opts}
  end

  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  def child_spec(opts),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
end
