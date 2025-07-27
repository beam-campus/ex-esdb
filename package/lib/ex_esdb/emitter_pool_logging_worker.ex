defmodule ExESDB.EmitterPoolLoggingWorker do
  @moduledoc """
  Logging worker responsible for handling EmitterPool logging events.
  
  This worker subscribes to emitter_pool logging events and processes them
  according to configured logging policies.
  """
  
  use GenServer
  require Logger
  
  alias Phoenix.PubSub
  alias ExESDB.StoreNaming
  alias ExESDB.Themes
  
  defstruct [
    :store_id,
    :logging_level,
    :terminal_output_enabled
  ]
  
  def start_link(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    name = StoreNaming.genserver_name(__MODULE__, store_id)
    
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def child_spec(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    
    %{
      id: StoreNaming.child_spec_id(__MODULE__, store_id),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end
  
  @impl GenServer
  def init(opts) do
    store_id = StoreNaming.extract_store_id(opts)
    logging_level = Keyword.get(opts, :emitter_pool_logging_level, :info)
    terminal_output = Keyword.get(opts, :emitter_pool_terminal_output, true)
    
    # Subscribe to emitter_pool logging events
    :ok = PubSub.subscribe(:ex_esdb_logging, "logging:emitter_pool")
    :ok = PubSub.subscribe(:ex_esdb_logging, "logging:store:#{store_id}")
    
    state = %__MODULE__{
      store_id: store_id,
      logging_level: logging_level,
      terminal_output_enabled: terminal_output
    }
    
    Logger.debug("EmitterPoolLoggingWorker started for store #{store_id}")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_info({:log_event, %{component: :emitter_pool} = event}, state) do
    process_logging_event(event, state)
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info({:log_event, _event}, state) do
    # Ignore events from other components
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  defp process_logging_event(event, state) do
    try do
      %{
        event_type: event_type,
        store_id: store_id,
        pid: pid,
        message: message,
        metadata: metadata
      } = event
      
      # Only process events for our store
      if store_id == state.store_id do
        case event_type do
          :startup ->
            handle_startup_event(pid, message, metadata, state)
          :shutdown ->
            handle_shutdown_event(pid, message, metadata, state)
          :action ->
            handle_action_event(pid, message, metadata, state)
          :error ->
            handle_error_event(pid, message, metadata, state)
          _ ->
            handle_generic_event(event_type, pid, message, metadata, state)
        end
      end
    rescue
      error ->
        Logger.warning("EmitterPoolLoggingWorker received malformed event: #{inspect(event)}, error: #{inspect(error)}")
    end
  end
  
  defp handle_startup_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      pool_name = Map.get(metadata, :pool_name, "unknown")
      sub_topic = Map.get(metadata, :sub_topic, "unknown")
      emitter_count = Map.get(metadata, :emitter_count, 0)
      
      IO.puts("")
      IO.puts("")
      IO.puts("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
      IO.puts("#{Themes.emitter_pool_success_msg(pid, "  🚀 EMITTER POOL STARTUP 🚀                      ")}")
      IO.puts("┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
      IO.puts("#{Themes.emitter_pool_success_msg(pid, "  Pool Name: #{pool_name}")}")
      IO.puts("#{Themes.emitter_pool_success_msg(pid, "  Store ID:  #{state.store_id}")}")
      IO.puts("#{Themes.emitter_pool_success_msg(pid, "  Topic:     #{sub_topic}")}")
      IO.puts("#{Themes.emitter_pool_success_msg(pid, "  Workers:   #{emitter_count}")}")
      IO.puts("#{Themes.emitter_pool_success_msg(pid, "  PID:       #{inspect(pid)}")}")
      IO.puts("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
      IO.puts("")
      IO.puts("")
    end
    
    Logger.info("[EmitterPool:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_shutdown_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      pool_name = Map.get(metadata, :pool_name, "unknown")
      sub_topic = Map.get(metadata, :sub_topic, "unknown")
      reason = Map.get(metadata, :reason, "Manual Stop")
      
      IO.puts("")
      IO.puts("")
      IO.puts("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
      IO.puts("#{Themes.emitter_pool_failure_msg(pid, "  🚨 EMITTER POOL SHUTDOWN 🚨                     ")}")
      IO.puts("┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫")
      IO.puts("#{Themes.emitter_pool_failure_msg(pid, "  Pool Name: #{pool_name}")}")
      IO.puts("#{Themes.emitter_pool_failure_msg(pid, "  Store ID:  #{state.store_id}")}")
      IO.puts("#{Themes.emitter_pool_failure_msg(pid, "  Topic:     #{sub_topic}")}")
      IO.puts("#{Themes.emitter_pool_failure_msg(pid, "  Reason:    #{reason}")}")
      IO.puts("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
      IO.puts("")
      IO.puts("")
    end
    
    Logger.warning("[EmitterPool:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_action_event(pid, message, metadata, state) do
    if state.terminal_output_enabled and state.logging_level in [:debug, :info] do
      IO.puts("#{Themes.emitter_pool_action_msg(pid, "[EmitterPool] #{message}")}")
    end
    
    Logger.info("[EmitterPool:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_error_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      IO.puts("#{Themes.emitter_pool_failure_msg(pid, "[EmitterPool:ERROR] #{message}")}")
    end
    
    Logger.error("[EmitterPool:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_generic_event(event_type, pid, message, metadata, state) do
    if state.terminal_output_enabled and state.logging_level == :debug do
      IO.puts("#{Themes.emitter_pool_action_msg(pid, "[EmitterPool:#{event_type}] #{message}")}")
    end
    
    Logger.debug("[EmitterPool:#{state.store_id}:#{event_type}] #{message}", metadata)
  end
end
