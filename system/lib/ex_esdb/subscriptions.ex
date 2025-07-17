defmodule ExESDB.Subscriptions do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  use Supervisor

  require Logger
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  ####### PLUMBING #######
  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    Supervisor.start_link(
      __MODULE__,
      opts,
      name: name
    )
  end

  @impl true
  def init(opts) do
    IO.puts("#{Themes.subscriptions(self(), "is UP.")}")

    children = [
      {ExESDB.SubscriptionsReader, opts},
      {ExESDB.SubscriptionsWriter, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
