defmodule ExESDB.StreamsReaderPool do
  @moduledoc """
    As part of the ExESDB.System,
  """
  use DynamicSupervisor

  alias ExESDB.Themes, as: Themes

  require Logger

  ######################## PLUMBING ########################
  @impl true
  def init(opts) do
    IO.puts("#{Themes.streams_reader_pool(self(), "is UP with #{inspect(opts)}")}")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
