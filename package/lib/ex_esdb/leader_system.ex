defmodule ExESDB.LeaderSystem do
  @moduledoc """
    This module supervises the Leader Subsystem.
  """
  use Supervisor
  require Logger
  alias ExESDB.Themes, as: Themes
  alias ExESDB.StoreNaming
  ############### PlUMBIng ############
  #
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
  def init(config) do
    store_id = StoreNaming.extract_store_id(config)
    Process.flag(:trap_exit, true)

    children = [
      # LeaderTracker must start first to establish subscription tracking infrastructure
      {ExESDB.LeaderTracker, config},
      # LeaderWorker depends on the tracking infrastructure being ready
      {ExESDB.LeaderWorker, config}
    ]

    # Use :rest_for_one because LeaderWorker depends on LeaderTracker
    result = Supervisor.init(children, strategy: :rest_for_one)
    IO.puts(Themes.leader_system(self(), "[#{store_id}] is UP!"))
    result
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
