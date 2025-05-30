defmodule ExESDB.App do
  @moduledoc """
  This module is used to start the ExESDB system.
  """
  use Application,
    otp_app: :ex_esdb

  alias ExESDB.Options, as: Options
  alias ExESDB.Themes, as: Themes

  require Logger
  require Phoenix.PubSub

  @impl true
  def start(_type, _args) do
    opts = Options.app_env()

    children = [
      {ExESDB.System, opts}
    ]

    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sigquit, :handle)

    spawn(fn -> handle_os_signal() end)

    Logger.warning("#{Themes.app(self())} is UP.")

    opts = [strategy: :one_for_one, name: EsESDB.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def handle_os_signal do
    receive do
      {:signal, :sigterm} ->
        Logger.warning("SIGTERM received. Stopping ExESDB")

        Process.sleep(2_000)
        ExESDB.System.stop(:sigterm)
        Application.stop(:ex_esdb)
        System.halt(0)

      msg ->
        IO.puts("Unknown signal: #{inspect(msg)}")
        Logger.warning("Received unknown signal: #{inspect(msg)}")
    end

    handle_os_signal()
  end

  @impl true
  def stop(state) do
    Logger.warning("STOPPING APP #{inspect(state, pretty: true)}")
  end
end
