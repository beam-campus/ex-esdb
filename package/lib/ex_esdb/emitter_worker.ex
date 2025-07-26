defmodule ExESDB.EmitterWorker do
  @moduledoc """
    As part of the ExESDB.System, 
    the EmitterWorker is responsible for managing the communication 
    between the Event Store and the PubSub mechanism.
  """
  use GenServer

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

  # Always emit events to :ex_esdb_events if the emitter is active
  defp emit(_pub_sub, topic, event) do
    if Process.get(:emitter_active) do
      :ex_esdb_events
      |> PubSub.broadcast(topic, {:events, [event]})
    else
      {:error, :not_active}
    end
  end

  @impl GenServer
  def init({store, sub_topic, subscriber}) do
    Process.flag(:trap_exit, true)
    scheduler_id = :erlang.system_info(:scheduler_id)
    topic = :emitter_group.topic(store, sub_topic)

    :ok = :emitter_group.join(store, sub_topic, self())
    Process.put(:emitter_active, true)

    # Enhanced prominent multi-line activation message
    IO.puts("")
    IO.puts("┌──────────────────────────────────────────────────────────────────────┐")
    IO.puts("#{Themes.emitter_worker(self(), "  ★ EMITTER WORKER ACTIVATION ★               ")}")
    IO.puts("├──────────────────────────────────────────────────────────────────────┤")
    IO.puts("#{Themes.emitter_worker(self(), "  Topic:     #{inspect(topic)}")}")
    IO.puts("#{Themes.emitter_worker(self(), "  Store:     #{store}")}")
    IO.puts("#{Themes.emitter_worker(self(), "  Scheduler: #{scheduler_id}")}")
    IO.puts("#{Themes.emitter_worker(self(), "  PID:       #{inspect(self())}")}")
    IO.puts("└──────────────────────────────────────────────────────────────────────┘")
    IO.puts("")

    {:ok, %{subscriber: subscriber, store: store, selector: sub_topic}}
  end

  @impl GenServer
  def terminate(reason, %{store: store, selector: selector}) do
    # Mark process as inactive to prevent further broadcasts
    Process.put(:emitter_active, false)

    # Enhanced prominent multi-line termination message
    IO.puts("")
    IO.puts("╔══════════════════════════════════════════════════════════════════════╗")
    IO.puts("#{Themes.emitter_worker(self(), "  💀 EMITTER WORKER TERMINATION 💀              ")}")
    IO.puts("╠══════════════════════════════════════════════════════════════════════╣")
    IO.puts("#{Themes.emitter_worker(self(), "  Reason:    #{inspect(reason)}")}")
    IO.puts("#{Themes.emitter_worker(self(), "  Store:     #{store}")}")
    IO.puts("#{Themes.emitter_worker(self(), "  Selector:  #{selector}")}")
    IO.puts("#{Themes.emitter_worker(self(), "  PID:       #{inspect(self())}")}")
    IO.puts("╚══════════════════════════════════════════════════════════════════════╝")
    IO.puts("")

    # Leave the emitter group and cleanup
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
    # Enhanced event processing logging
    event_id = Map.get(event, :event_id, "unknown")
    event_type = Map.get(event, :event_type, "unknown")

    IO.puts(
      "#{Themes.emitter_worker(self(), "⚡ BROADCASTING Event: #{event_id}(#{event_type}) -> Topic: #{topic}")}"
    )

  case subscriber do
      nil ->
        emit(nil, topic, event)
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
    # Enhanced local forwarding logging
    event_id = Map.get(event, :event_id, "unknown")
    event_type = Map.get(event, :event_type, "unknown")

    IO.puts(
      "#{Themes.emitter_worker(self(), "🔄 FORWARDING Event: #{event_id}(#{event_type}) -> Local Topic: #{topic}")}"
    )

  case subscriber do
      nil ->
        emit(nil, topic, event)
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
    updated_state = %{state | subscriber: new_subscriber}
    {:noreply, updated_state}
  end
end
