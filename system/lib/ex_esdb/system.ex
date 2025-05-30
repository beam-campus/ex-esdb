defmodule ExESDB.System do
  @moduledoc """
    This module is the top level supervisor for the ExESDB system.
    It is responsible for supervising:
    - The PubSub mechanism
    - the Event Store
    - the Cluster
  """
  use Supervisor

  alias ExESDB.Themes, as: Themes

  require Logger
  require Phoenix.PubSub

  defp add_pub_sub(opts) do
    pub_sub = Keyword.get(opts, :pub_sub)

    case pub_sub do
      nil ->
        add_pub_sub([pub_sub: :native] ++ opts)

      :native ->
        {ExESDB.PubSub, opts}

      _ ->
        {Phoenix.PubSub, name: pub_sub}
    end
  end

  def stop(reason) do
    Process.exit(self(), reason)
  end

  @impl true
  def init(opts) do
    Logger.warning("#{Themes.system(self())} is UP")

    children = [
      add_pub_sub(opts),
      {ExESDB.EventStore, opts},
      {ExESDB.Cluster, opts},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.EmitterPools}
    ]

    Supervisor.init(
      children,
      strategy: :one_for_one
    )
  end

  def start_link(opts),
    do:
      Supervisor.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  def start(opts) do
    case start_link(opts) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "failed to start eventstores supervisor: #{inspect(reason)}"
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end
