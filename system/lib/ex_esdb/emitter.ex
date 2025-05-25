defmodule ExESDB.Emitters do
  @moduledoc """
    As part of the ExESDB.System, ExESDB.Emitters is responsible for managing the
    lifetime of the Emitter processes.
  """

  alias ExESDB.Options

  # use DynamicSupervisor
  # @impl DynamicSupervisor
  # def init(_) do
  #   DynamicSupervisor.init(strategy: :one_for_one)
  # end
  #

  def start_all_emitter(store, pool_size \\ 3) do
    filter = :ex_esdb_filter.by_stream("$all")
    start_emitter(store, "$all", pool_size, filter)
  end

  def start_stream_emitter(store, stream, pool_size \\ 3) do
    filter = :ex_esdb_filter.by_stream(stream)
    start_emitter(store, stream, pool_size, filter)
  end

  def start_type_emitter(store, type, pool_size \\ 3) do
    filter = :ex_esdb_filter.by_event_type(type)
    start_emitter(store, type, pool_size, filter)
  end

  def start_custom_emitter(store, id, pattern, pool_size \\ 3) do
    filter = :ex_esdb_filter.by_event_pattern(pattern)
    start_emitter(store, id, pool_size, filter)
  end

  defp start_emitter(store, id, pool_size, filter) do
    pubsub = Options.pub_sub()

    DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {ExESDB.EmitterPools, self()}},
      {ExESDB.EmitterPool, {store, id, pubsub, pool_size, filter}}
    )
  end
end

defmodule ExESDB.EmitterPool do
  @moduledoc """
    As part of the ExESDB.System,
  """
  use Supervisor

  require Logger
  require ExESDB.Themes, as: Themes

  def start_link({store, id, pubsub, pool_size, filter}) do
    Supervisor.start_link(__MODULE__, {store, id, pubsub, pool_size, filter},
      name: :"#{store}:#{id}_emitter_pool"
    )
  end

  @impl Supervisor
  def init({store, id, pubsub, pool_size, filter}) do
    scheduler_id = :erlang.system_info(:scheduler_id)

    emitters =
      :ex_esdb_triggers.setup_emitters(store, id, filter, pool_size)

    children =
      for emitter <- emitters do
        Supervisor.child_spec({ExESDB.EmitterWorker, {store, id, pubsub, emitter}},
          id: emitter
        )
      end

    Logger.warning("
      Starting Children: \n#{inspect(children)}
      ")

    Logger.warning("#{Themes.emitter_pool(self())} is UP on scheduler #{inspect(scheduler_id)}")
    Supervisor.init(children, strategy: :one_for_one)
  end
end

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

  defp emit(pub_sub, topic, event),
    do:
      pub_sub
      |> PubSub.broadcast(topic, {:event_emitted, event})

  @impl GenServer
  def init({store, id, pubsub}) do
    scheduler_id = :erlang.system_info(:scheduler_id)
    topic = :emitter_group.topic(store, id)
    :ok = :emitter_group.join(store, id, self())

    Logger.warning(
      "#{Themes.emitter_worker(self())} for #{inspect(topic, pretty: true)} is UP on scheduler #{inspect(scheduler_id)}"
    )

    {:ok, pubsub}
  end

  def start_link({store, id, pubsub, emitter}),
    do:
      GenServer.start_link(
        __MODULE__,
        {store, id, pubsub},
        name: emitter
      )

  @impl true
  def handle_info({:broadcast, topic, event}, pubsub) do
    pubsub
    |> emit(topic, event)

    Logger.warning(
      "#{Themes.emitter_worker(self())} BROADCAST #{inspect(event, pretty: true)} => #{inspect(topic, pretty: true)}"
    )

    {:noreply, pubsub}
  end

  @impl true
  def handle_info({:forward_to_local, topic, event}, pubsub) do
    pubsub
    |> emit(topic, event)

    Logger.warning(
      "#{Themes.emitter_worker(self())} FORWARD_TO_LOCAL #{inspect(event, pretty: true)} => #{inspect(topic, pretty: true)}"
    )

    {:noreply, pubsub}
  end

  @impl true
  def handle_info(_, pubsub) do
    {:noreply, pubsub}
  end
end
