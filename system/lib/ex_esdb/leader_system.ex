defmodule ExESDB.LeaderSystem do
  @moduledoc """
    This module supervises the Leader Subsystem.
  """
  use Supervisor
  require Logger
  ############### PlUMBIng ############
  #
  def start_link(opts),
    do:
      Supervisor.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  @impl true
  def init(config) do
    Logger.info("LeaderSystem #{inspect(self())} is UP!")
    Process.flag(:trap_exit, true)

    children = [
      {ExESDB.LeaderWorker, config},
      {ExESDB.LeaderTracker, config}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
