defmodule ExESDB.LeaderSystem do
  @moduledoc """
    This module supervises the Leader Subsystem.
  """
  use Supervisor
  require Logger
  alias ExESDB.Themes, as: Themes
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
    IO.puts("#{Themes.leader_system(self(), "is UP!")}")
    Process.flag(:trap_exit, true)

    children = [
      # LeaderTracker must start first to establish subscription tracking infrastructure
      {ExESDB.LeaderTracker, config},
      # LeaderWorker depends on the tracking infrastructure being ready
      {ExESDB.LeaderWorker, config}
    ]

    # Use :rest_for_one because LeaderWorker depends on LeaderTracker
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
