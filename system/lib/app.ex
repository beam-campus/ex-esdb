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
    # Support umbrella configuration patterns
    # Check if there's an :otp_app in the application environment
    otp_app = Application.get_env(:ex_esdb, :otp_app, :ex_esdb)
    
    # Set the context for configuration access
    Options.set_context(otp_app)
    
    config = Options.app_env(otp_app)
    store_id = config[:store_id]
    Logger.warning("Attempting to start ExESDB with options: #{inspect(config, pretty: true)}")
    Logger.warning("Using configuration from OTP app: #{inspect(otp_app)}")

    # Pass the otp_app to the system configuration
    enhanced_config = Keyword.put(config, :otp_app, otp_app)

    children = [
      {ExESDB.System, enhanced_config}
    ]

    opts = [strategy: :one_for_one, name: ExESDB.Supervisor]
    res = Supervisor.start_link(children, opts)

    IO.puts("#{Themes.app(self(), "is UP for store #{inspect(store_id)}")}")

    res
  end

  @impl true
  def stop(state) do
    ExESDB.System.stop(:normal)
    Logger.warning("STOPPING APP #{inspect(state, pretty: true)}")
  end
end
