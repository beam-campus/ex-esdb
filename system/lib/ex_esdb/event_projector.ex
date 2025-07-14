defmodule ExESDB.EventProjector do
  @moduledoc """
    This module contains the event projector functionality
  """
  use GenServer

  alias ExESDB.Themes, as: Themes
  alias Phoenix.PubSub, as: PubSub

  require Logger

  @impl true
  def handle_info({:event, event}, state) do
    Logger.info("#{Themes.projector(self(), "Received event: #{inspect(event, pretty: true)}")}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Logger.info("#{Themes.projector(self(), "Projector DOWN")}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("#{Themes.projector(self(), "Unknown message: #{inspect(msg, pretty: true)}")}")
    {:noreply, state}
  end

  ##### PLUMBING #####
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Logger.info("#{Themes.projector(self(), "is UP.")}")
    opts[:pub_sub]
    |> PubSub.subscribe(to_string(opts[:store_id]))
    {:ok, opts}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("#{Themes.projector(self(), "⚠️  Shutting down gracefully. Reason: #{inspect(reason)}")}")
    # Unsubscribe from PubSub
    state[:pub_sub]
    |> PubSub.unsubscribe(to_string(state[:store_id]))
    :ok
  end

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: __MODULE__
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000,
    }
  end

end
