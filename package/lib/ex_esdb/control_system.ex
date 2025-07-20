defmodule ExESDB.ControlSystem do
  @moduledoc """
  Supervisor for the Control Plane and PubSub systems.

  This module creates a separate supervision tree to manage 
  the PubSub and ControlPlane components used for internal 
  event-driven coordination.
  """
  use Supervisor

  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming

  @impl true
  def init(opts) do
    children = [
      {ExESDB.PubSub, opts},
      {ExESDB.ControlPlane, opts}
    ]

    IO.puts(Themes.core_system(self(), "ControlSystem is UP"))

    Supervisor.init(children,
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 60
    )
  end

  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)

    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor
    }
  end
end

