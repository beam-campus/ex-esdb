defmodule ExESDB.LeaderWorker do
  @moduledoc """
    This module contains the leader's reponsibilities for the cluster.
  """
  use GenServer
  require Logger
  alias ExESDB.Emitters
  alias ExESDB.SubscriptionsReader, as: SubsR
  alias ExESDB.SubscriptionsWriter, as: SubsW
  alias ExESDB.Themes, as: Themes
  ############ API ############
  def activate(store) do
    GenServer.call(
      __MODULE__,
      {:save_default_subscriptions, store}
    )

    GenServer.cast(
      __MODULE__,
      {:activate, store}
    )
  end

  ########## HANDLE_CAST ##########
  @impl true
  def handle_cast({:activate, store}, state) do
    IO.puts("\n#{Themes.leader_worker(self(), "🚀 ACTIVATING LEADERSHIP RESPONSIBILITIES")}")
    IO.puts("  🏆 Node: #{inspect(node())}")
    IO.puts("  📊 Store: #{inspect(store)}")

    subscriptions =
      store
      |> SubsR.get_subscriptions()

    subscription_count = Enum.count(subscriptions)

    case subscription_count do
      0 ->
        IO.puts("  📝 No active subscriptions to manage")

      1 ->
        IO.puts("  📝 Managing 1 active subscription")

      num ->
        IO.puts("  📝 Managing #{num} active subscriptions")
    end

    if subscription_count > 0 do
      IO.puts("\n  Starting emitters for active subscriptions:")

      subscriptions
      |> Enum.each(fn {key, subscription} ->
        IO.puts("    ⚙️  Starting emitter for: #{inspect(key)}")

        store
        |> Emitters.start_emitter_pool(subscription)
      end)
    end

    IO.puts("\n  ✅ Leadership activation complete\n")

    {:noreply, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Leader received unexpected CAST: #{inspect(msg)}")
    {:noreply, state}
  end

  ################ HANDLE_INFO ############
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Leader received unexpected INFO: #{inspect(msg)}")
    {:noreply, state}
  end

  ############# HANDLE_CALL ##########
  @impl true
  def handle_call({:save_default_subscriptions, store}, _from, state) do
    res =
      store
      |> SubsW.put_subscription(:by_stream, "$all", "all-events")

    {:reply, {:ok, res}, state}
  end

  @impl true
  def handle_call(msg, _from, state) do
    Logger.warning("Leader received unexpected CALL: #{inspect(msg)}")
    {:reply, :ok, state}
  end

  ############# PLUMBING #############
  #
  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  @impl true
  def terminate(reason, _state) do
    Logger.warning("#{Themes.cluster(self(), "terminating with reason: #{inspect(reason)}")}")
    :ok
  end

  @impl true
  def init(config) do
    IO.puts("#{Themes.leader_worker(self(), "is UP!")}")
    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def child_spec(opts),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 10_000,
      type: :worker
    }
end
