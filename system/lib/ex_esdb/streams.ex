defmodule ExESDB.Streams do
  @moduledoc """
    The ExESDB Streams SubSystem.
  """
  use Supervisor

  require Logger

  def start_link(opts),
    do:
      Supervisor.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  @impl true
  def init(_) do
    children = [
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.StreamsWriters},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.StreamsReaders}
    ]

    ret = Supervisor.init(children, strategy: :one_for_one)
    Logger.info("Streams #{inspect(self())} is UP.")
    ret
  end
end
