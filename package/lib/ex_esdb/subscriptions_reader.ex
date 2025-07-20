defmodule ExESDB.SubscriptionsReader do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  use GenServer

  import ExESDB.Khepri.Conditions

  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming
  require Logger

  def get_subscriptions(store) do
    name = StoreNaming.genserver_name(__MODULE__, store)
    GenServer.call(
      name,
      {:get_subscriptions, store}
    )
  end

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
  def init(opts) do
    Process.flag(:trap_exit, true)
    IO.puts("#{Themes.subscriptions_reader(self(), "is UP")}")
    {:ok, opts}
  end

  @impl true
  def terminate(reason, _state) do
    IO.puts("#{Themes.subscriptions_reader(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}")}")
    :ok
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
