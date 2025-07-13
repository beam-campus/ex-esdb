defmodule ExESDB.SubscriptionsReader do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  use GenServer

  import ExESDB.Khepri.Conditions

  require Logger

  def get_subscriptions(store),
    do:
      GenServer.call(
        __MODULE__,
        {:get_subscriptions, store}
      )

  ################ HANDLE_CALL #############
  @impl GenServer
  def handle_call({:get_subscriptions, store}, _from, state) do
    case store
         |> :khepri.get_many([
           :subscriptions,
           if_all(
             conditions: [
               if_path_matches(regex: :any),
               if_has_payload(has_payload: true)
             ]
           )
         ]) do
      {:ok, result} ->
        {:reply, result, state}

      _ ->
        {:reply, [], state}
    end
  end

  ############### PLUMBING ###############
  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  @impl true
  def init(opts) do
    Logger.info("SubscriptionsReader #{inspect(self())} is UP")
    {:ok, opts}
  end

  def child_spec(opts),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
end
