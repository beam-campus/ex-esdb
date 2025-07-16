defmodule ExESDB.TestCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias ExESDB.Options, as: Options
  alias ExESDB.System, as: ESDBSystem

  require Logger

  setup do
    {:ok, esdb_meta} = start_supervised({ESDBSystem, Options.app_env(:ex_esdb)})
    Logger.debug("esdb_meta: #{inspect(esdb_meta, pretty: true)}")
    [esdb_meta: esdb_meta]
  end

end
