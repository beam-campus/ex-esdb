defmodule ExESDB.StreamsWriterPool do
  @moduledoc """
    As part of the ExESDB.System,
  """
  use DynamicSupervisor

  require Logger

  ######################## PLUMBING ########################
  @impl true
  def init(opts) do
    Logger.info("StreamsWriterPool #{inspect(self())} is UP with #{inspect(opts)}")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
