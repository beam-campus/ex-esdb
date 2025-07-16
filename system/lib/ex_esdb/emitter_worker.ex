defmodule ExESDB.EmitterWorker do
  @moduledoc """
    As part of the ExESDB.System, 
    the EmitterWorker is responsible for managing the communication 
    between the Event Store and the PubSub mechanism.
  """
  use GenServer

  alias ExESDB.Options, as: Options
  alias Phoenix.PubSub, as: PubSub

  require ExESDB.Themes, as: Themes

  require Logger

  defp send_or_kill_pool(pid, event, store, selector) do
    if Process.alive?(pid) do
      Process.send(pid, {:events, [event]}, [])
    else
      ExESDB.EmitterPool.stop(store, selector)
    end
  end

  defp emit(pub_sub, topic, event) do
    pub_sub
    |> PubSub.broadcast(topic, {:events, [event]})
  end

  @impl GenServer
  def init({store, sub_topic, subscriber}) do
    Process.flag(:trap_exit, true)
    scheduler_id = :erlang.system_info(:scheduler_id)
    topic = :emitter_group.topic(store, sub_topic)
    :ok = :emitter_group.join(store, sub_topic, self())

    msg = "for #{inspect(topic)} is UP on scheduler #{inspect(scheduler_id)}"

    IO.puts("#{Themes.emitter_worker(self(), msg)}")

    {:ok, %{subscriber: subscriber, store: store, selector: sub_topic}}
  end

  @impl GenServer
  def terminate(reason, %{store: store, selector: selector}) do
    msg = "is TERMINATED with reason #{inspect(reason)}"
    IO.puts("#{Themes.emitter_worker(self(), msg)}")
    :ok = :emitter_group.leave(store, selector, self())
    :ok
  end

  def start_link({store, sub_topic, subscriber, emitter}),
    do:
      GenServer.start_link(
        __MODULE__,
        {store, sub_topic, subscriber},
        name: emitter
      )

  def child_spec({store, sub_topic, subscriber, emitter}) do
    %{
      id: Module.concat(__MODULE__, emitter),
      start: {__MODULE__, :start_link, [{store, sub_topic, subscriber, emitter}]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @impl true
  def handle_info(
        {:broadcast, topic, event},
        %{subscriber: subscriber, store: store, selector: selector} = state
      ) do
    case subscriber do
      nil ->
        pubsub = Options.pub_sub()

        pubsub
        |> emit(topic, event)

      pid ->
        send_or_kill_pool(pid, event, store, selector)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:forward_to_local, topic, event},
        %{subscriber: subscriber, store: store, selector: selector} = state
      ) do
    case subscriber do
      nil ->
        pubsub = Options.pub_sub()

        pubsub
        |> emit(topic, event)

      pid ->
        send_or_kill_pool(pid, event, store, selector)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:events, events}, state) when is_list(events) do
    # Handle events messages - these might come from feedback loops or external systems
    # Just ignore them since they're already processed events
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Received unexpected message #{inspect(msg)} on #{inspect(self())}")

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:update_subscriber, new_subscriber}, state) do
    Logger.info("EmitterWorker updating subscriber from #{inspect(state.subscriber)} to #{inspect(new_subscriber)}")
    updated_state = %{state | subscriber: new_subscriber}
    {:noreply, updated_state}
  end
end
