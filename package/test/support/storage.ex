defmodule ExESDB.TestSupport.Storage do
  @moduledoc false

  alias ExESDB.Options, as: Options

  require Logger

  def wait_for_event_store(timeout \\ 5_000) when is_integer(timeout) do
    task = Task.async(&esdb_check/0)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        {:error, :timeout}
    end
  end

  defp esdb_check do
    case ExESDB.System.start(Options.app_env(:ex_esdb)) do
      {:ok, _} ->
        :timer.sleep(1_000)
        :ok

      _ ->
        :timer.sleep(1_000)
        esdb_check()
    end
  end

  def store do
    Options.store_id()
  end
end
