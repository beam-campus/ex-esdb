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

    # Enhanced prominent multi-line pool startup message
    pool_name = name(store, sub_topic)
    emitter_count = length(emitter_names)
    
    IO.puts("")
    IO.puts("")
    IO.puts("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
    IO.puts("#{Themes.emitter_pool(self(), "  🚀 EMITTER POOL STARTUP 🚀                      ")}")
    IO.puts("┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
    IO.puts("#{Themes.emitter_pool(self(), "  Pool Name: #{pool_name}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  Store ID:  #{store}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  Topic:     #{sub_topic}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  Workers:   #{emitter_count}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  PID:       #{inspect(self())}")}")
    IO.puts("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
    IO.puts("")
    IO.puts("")

    Supervisor.init(children, strategy: :one_for_one)
  end

  def stop(store, sub_topic) do
    pool_name = name(store, sub_topic)
    
    # Enhanced prominent multi-line pool shutdown message
    IO.puts("")
    IO.puts("")
    IO.puts("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
    IO.puts("#{Themes.emitter_pool(self(), "  🚨 EMITTER POOL SHUTDOWN 🚨                     ")}")
    IO.puts("┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
    IO.puts("#{Themes.emitter_pool(self(), "  Pool Name: #{pool_name}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  Store ID:  #{store}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  Topic:     #{sub_topic}")}")
    IO.puts("#{Themes.emitter_pool(self(), "  Reason:    Manual Stop")}")
    IO.puts("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
    IO.puts("")
    IO.puts("")
    
    Supervisor.stop(pool_name)
  end
end
