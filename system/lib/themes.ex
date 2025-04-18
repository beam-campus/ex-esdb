defmodule ExESDB.Themes do
  @moduledoc false
  alias BeamCampus.ColorFuncs, as: CF

  def app(pid),
    do: "ESDB_APP [#{CF.black_on_blue()}#{inspect(pid)}#{CF.reset()}]"

  def system(pid),
    do: "ESDB_SYSTEM [#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}]"

  def store(pid),
    do: "ESDB_STORE [#{CF.black_on_green()}#{inspect(pid)}#{CF.reset()}]"

  def cluster(pid),
    do: "ESDB_CLUSTER [#{CF.yellow_on_red()}#{inspect(pid)}#{CF.reset()}]"

  def projector(pid),
    do: "ESDB_PROJECTOR [#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}]"

  def monitor(pid),
    do: "ESDB_MONITOR [#{CF.yellow_on_magenta()}#{inspect(pid)}#{CF.reset()}]"

  def emitter(pid),
    do: "ESDB_EMITTER [#{CF.black_on_yellow()}#{inspect(pid)}#{CF.reset()}]"
end
