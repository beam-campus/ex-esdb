defmodule ExESDB.EmitterWorkerLoggingWorker do
  @moduledoc """
  Logging worker responsible for handling EmitterWorker logging events.
  
  This worker subscribes to emitter_worker logging events and processes them
  according to configured logging policies. Since EmitterWorkers can be very
  chatty, this worker provides more fine-grained control over what gets logged.
  """
  
  use GenServer
  require Logger
  
  alias Phoenix.PubSub
  alias ExESDB.StoreNaming
  alias ExESDB.Themes
  
  defstruct [
    :store_id,
    :logging_level,
    :terminal_output_enabled,
    :log_worker_actions,
    :log_health_events
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
    logging_level = Keyword.get(opts, :emitter_worker_logging_level, :info)
    terminal_output = Keyword.get(opts, :emitter_worker_terminal_output, false) # Default to false - workers are chatty
    log_worker_actions = Keyword.get(opts, :emitter_worker_log_actions, false) # Default to false - very verbose
    log_health_events = Keyword.get(opts, :emitter_worker_log_health, true)
    
    # Subscribe to emitter_worker logging events
    :ok = PubSub.subscribe(:ex_esdb_logging, "logging:emitter_worker")
    :ok = PubSub.subscribe(:ex_esdb_logging, "logging:store:#{store_id}")
    
    state = %__MODULE__{
      store_id: store_id,
      logging_level: logging_level,
      terminal_output_enabled: terminal_output,
      log_worker_actions: log_worker_actions,
      log_health_events: log_health_events
    }
    
    Logger.debug("EmitterWorkerLoggingWorker started for store #{store_id}")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_info({:log_event, %{component: :emitter_worker} = event}, state) do
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
          :health ->
            handle_health_event(pid, message, metadata, state)
          :error ->
            handle_error_event(pid, message, metadata, state)
          _ ->
            handle_generic_event(event_type, pid, message, metadata, state)
        end
      end
    rescue
      error ->
        Logger.warning("EmitterWorkerLoggingWorker received malformed event: #{inspect(event)}, error: #{inspect(error)}")
    end
  end
  
  defp handle_startup_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      topic = Map.get(metadata, :topic, "unknown")
      subscriber = Map.get(metadata, :subscriber, "unknown")
      scheduler_id = Map.get(metadata, :scheduler_id, "unknown")
      
      IO.puts("")
      IO.puts("┌──────────────────────────────────────────────────────────────────────┐")
      IO.puts("#{Themes.emitter_worker_success_msg(pid, "  ★ EMITTER WORKER ACTIVATION ★               ")}")
      IO.puts("├──────────────────────────────────────────────────────────────────────┤")
      IO.puts("#{Themes.emitter_worker_success_msg(pid, "  Topic:      #{inspect(topic)}")}")
      IO.puts("#{Themes.emitter_worker_success_msg(pid, "  Store:      #{state.store_id}")}")
      IO.puts("#{Themes.emitter_worker_success_msg(pid, "  Scheduler:  #{scheduler_id}")}")
      IO.puts("#{Themes.emitter_worker_success_msg(pid, "  PID:        #{inspect(pid)}")}")
      IO.puts("#{Themes.emitter_worker_success_msg(pid, "  Subscriber: #{inspect(subscriber)}")}")
      IO.puts("└──────────────────────────────────────────────────────────────────────┘")
      IO.puts("")
    end
    
    Logger.info("[EmitterWorker:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_shutdown_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      reason = Map.get(metadata, :reason, "unknown")
      selector = Map.get(metadata, :selector, "unknown")
      subscriber = Map.get(metadata, :subscriber, "unknown")
      
      IO.puts("")
      IO.puts("╔══════════════════════════════════════════════════════════════════════╗")
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "  💀 EMITTER WORKER TERMINATION 💀              ")}")
      IO.puts("╠══════════════════════════════════════════════════════════════════════╣")
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "  Reason:     #{inspect(reason)}")}")
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "  Store:      #{state.store_id}")}")
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "  Selector:   #{selector}")}")
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "  Subscriber: #{inspect(subscriber)}")}")
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "  PID:        #{inspect(pid)}")}")
      IO.puts("╚══════════════════════════════════════════════════════════════════════╝")
      IO.puts("")
    end
    
    Logger.warning("[EmitterWorker:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_action_event(pid, message, metadata, state) do
    # Only log actions if specifically enabled (they're very verbose)
    if state.log_worker_actions do
      if state.terminal_output_enabled and state.logging_level in [:debug, :info] do
        IO.puts("#{Themes.emitter_worker_action_msg(pid, "[EmitterWorker] #{message}")}")
      end
      
      Logger.debug("[EmitterWorker:#{state.store_id}] #{message}", metadata)
    end
  end
  
  defp handle_health_event(pid, message, metadata, state) do
    if state.log_health_events do
      if state.terminal_output_enabled and state.logging_level in [:debug, :info] do
        IO.puts("#{Themes.emitter_worker_health_msg(pid, "[EmitterWorker:Health] #{message}")}")
      end
      
      Logger.info("[EmitterWorker:#{state.store_id}:Health] #{message}", metadata)
    end
  end
  
  defp handle_error_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      IO.puts("#{Themes.emitter_worker_failure_msg(pid, "[EmitterWorker:ERROR] #{message}")}")
    end
    
    Logger.error("[EmitterWorker:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_generic_event(event_type, pid, message, metadata, state) do
    if state.terminal_output_enabled and state.logging_level == :debug do
      IO.puts("#{Themes.emitter_worker_action_msg(pid, "[EmitterWorker:#{event_type}] #{message}")}")
    end
    
    Logger.debug("[EmitterWorker:#{state.store_id}:#{event_type}] #{message}", metadata)
  end
end
