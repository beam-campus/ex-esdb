defmodule ExESDB.EventProjector do
  @moduledoc """
    This module contains the event projector functionality
  """
  use GenServer

  alias Phoenix.PubSub, as: PubSub
  alias BCUtils.ColorFuncs, as: CF

  require Logger

  @impl true
  def handle_info({:event, event}, state) do
    Logger.info("PROJECTOR [#{CF.black_on_white()}#{inspect(self())}#{CF.reset()}] => Received event: #{inspect(event, pretty: true)}",
      module: __MODULE__,
      component: :projector,
      pid: self(),
      event: event
    )
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Logger.info("PROJECTOR [#{CF.black_on_white()}#{inspect(self())}#{CF.reset()}] => Projector DOWN",
      module: __MODULE__,
      component: :projector,
      pid: self()
    )
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("PROJECTOR [#{CF.black_on_white()}#{inspect(self())}#{CF.reset()}] => Unknown message: #{inspect(msg, pretty: true)}",
      module: __MODULE__,
      component: :projector,
      pid: self(),
      message: msg
    )
    {:noreply, state}
  end

  ##### PLUMBING #####
  @impl true
  def init(opts) do
    Logger.info("PROJECTOR [#{CF.black_on_white()}#{inspect(self())}#{CF.reset()}] is UP.",
      module: __MODULE__,
      component: :projector,
      pid: self()
    )
    opts[:pub_sub]
    |> PubSub.subscribe(to_string(opts[:store_id]))
    {:ok, opts}
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
