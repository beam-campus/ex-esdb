defmodule ExESDB.LeaderWorker do
  @moduledoc """
    This module contains the leader's reponsibilities for the cluster.
  """
  use GenServer
  require Logger
  alias ExESDB.Emitters
  alias ExESDB.SubscriptionsReader, as: SubsR
  alias ExESDB.SubscriptionsWriter, as: SubsW
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
    Logger.info("🚀 ACTIVATING LEADERSHIP RESPONSIBILITIES",
      component: :leader_worker,
      pid: self(),
      arrow: true
    )
    
    Logger.info("🏆 Node: #{inspect(node())}",
      component: :leader_worker,
      pid: self(),
      indent: 1
    )
    
    Logger.info("📊 Store: #{inspect(store)}",
      component: :leader_worker,
      pid: self(),
      indent: 1
    )

    subscriptions =
      store
      |> SubsR.get_subscriptions()

    subscription_count = Enum.count(subscriptions)

    case subscription_count do
      0 ->
        Logger.info("📝 No active subscriptions to manage",
          component: :leader_worker,
          pid: self(),
          indent: 1
        )

      1 ->
        Logger.info("📝 Managing 1 active subscription",
          component: :leader_worker,
          pid: self(),
          indent: 1
        )

      num ->
        Logger.info("📝 Managing #{num} active subscriptions",
          component: :leader_worker,
          pid: self(),
          indent: 1
        )
    end

    if subscription_count > 0 do
      Logger.info("Starting emitters for active subscriptions:",
        component: :leader_worker,
        pid: self(),
        indent: 1
      )

      subscriptions
      |> Enum.each(fn {key, subscription} ->
        Logger.info("⚙️  Starting emitter for: #{inspect(key)}",
          component: :leader_worker,
          pid: self(),
          indent: 2
        )

        store
        |> Emitters.start_emitter_pool(subscription)
      end)
    end

    Logger.info("✅ Leadership activation complete",
      component: :leader_worker,
      pid: self(),
      indent: 1
    )

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
    Logger.warning("terminating with reason: #{inspect(reason)}",
      component: :leader_worker,
      pid: self()
    )
    :ok
  end

  @impl true
  def init(config) do
    Logger.info("is UP!",
      component: :leader_worker,
      pid: self()
    )
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
