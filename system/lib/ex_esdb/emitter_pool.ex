defmodule ExESDB.EmitterPool do
  @moduledoc false
  use Supervisor

  require Logger
  alias ExESDB.Themes, as: Themes

  def name(store, sub_topic),
    do: :"#{store}:#{sub_topic}_emitter_pool"

  def start_link({store, sub_topic, subscriber, pool_size, filter}) do
    Supervisor.start_link(
      __MODULE__,
      {store, sub_topic, subscriber, pool_size, filter},
      name: name(store, sub_topic)
    )
  end

  @impl Supervisor
  def init({store, sub_topic, subscriber, pool_size, filter}) do
    emitter_names =
      store
      |> :emitter_group.setup_emitter_mechanism(sub_topic, filter, pool_size)

    children =
      for emitter <- emitter_names do
        Supervisor.child_spec(
          {ExESDB.EmitterWorker, {store, sub_topic, subscriber, emitter}},
          id: emitter
        )
      end

    msg = "for [#{name(store, sub_topic)}] started with #{length(emitter_names)} emitters"
    IO.puts("#{Themes.emitter_pool(self(), msg)}")

    Supervisor.init(children, strategy: :one_for_one)
  end

  def stop(store, sub_topic), do: Supervisor.stop(name(store, sub_topic))
end
