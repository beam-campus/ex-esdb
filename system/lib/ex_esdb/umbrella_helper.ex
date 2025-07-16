defmodule ExESDB.UmbrellaHelper do
  @moduledoc """
  Helper module for starting ExESDB with umbrella configuration patterns.
  
  This module provides functions to start ExESDB with app-specific configurations
  when used in umbrella applications.
  """
  
  alias ExESDB.Options
  
  @doc """
  Start ExESDB with configuration from a specific OTP app.
  
  This function configures ExESDB to read its configuration from the specified
  OTP app instead of the global :ex_esdb application.
  
  ## Parameters
  
  * `otp_app` - The OTP application name to read configuration from
  
  ## Examples
  
      # In your reckon app's application.ex:
      def start(_type, _args) do
        children = [
          # Other children...
          ExESDB.UmbrellaHelper.child_spec(:reckon_accounts)
        ]
        
        Supervisor.start_link(children, strategy: :one_for_one)
      end
  """
  def child_spec(otp_app) when is_atom(otp_app) do
    config = Options.app_env(otp_app)
    enhanced_config = Keyword.put(config, :otp_app, otp_app)
    
    %{
      id: {:ex_esdb, otp_app},
      start: {ExESDB.System, :start_link, [enhanced_config]},
      type: :supervisor
    }
  end
  
  @doc """
  Start ExESDB with configuration from a specific OTP app.
  
  This is a convenience function that directly starts the ExESDB system
  with the specified OTP app configuration.
  """
  def start_link(otp_app) when is_atom(otp_app) do
    config = Options.app_env(otp_app)
    enhanced_config = Keyword.put(config, :otp_app, otp_app)
    
    ExESDB.System.start_link(enhanced_config)
  end
  
  @doc """
  Configure ExESDB to use the specified OTP app for configuration.
  
  This function sets up ExESDB to use app-specific configuration by
  setting the :otp_app configuration key.
  """
  def configure(otp_app) when is_atom(otp_app) do
    Application.put_env(:ex_esdb, :otp_app, otp_app)
  end
end
