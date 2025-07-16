defmodule ExESDB.SystemTest do
  use ExUnit.Case
  doctest ExESDB.System

  require Logger

  alias ExESDB.System, as: ESDBSystem
  alias ExESDB.EventStore, as: EventStore
  alias ExESDB.Options, as: Options

  @tag :skip
  test "that the ExESDB System starts the EventStore" do
    opts = Options.app_env(:ex_esdb)
    res = ESDBSystem.start(opts)
    Logger.debug("System pid: #{inspect(res, pretty: true)}")
  end
end
