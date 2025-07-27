defmodule ExESDB.EmitterSystemLoggingWorker do
  @moduledoc """
  Logging worker responsible for handling EmitterSystem logging events.
  
  This worker subscribes to emitter_system logging events and processes them
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
    logging_level = Keyword.get(opts, :emitter_system_logging_level, :info)
    terminal_output = Keyword.get(opts, :emitter_system_terminal_output, true)
    
    # Subscribe to emitter_system logging events
    :ok = PubSub.subscribe(:ex_esdb_logging, "logging:emitter_system")
    :ok = PubSub.subscribe(:ex_esdb_logging, "logging:store:#{store_id}")
    
    state = %__MODULE__{
      store_id: store_id,
      logging_level: logging_level,
      terminal_output_enabled: terminal_output
    }
    
    Logger.debug("EmitterSystemLoggingWorker started for store #{store_id}")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_info({:log_event, %{component: :emitter_system} = event}, state) do
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
  end
  
  defp handle_startup_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      IO.puts("")
      IO.puts("═════════════════════════════════════════════════════════════")
      IO.puts("#{Themes.emitter_system_success_msg(pid, "  🔥 EMITTER SYSTEM STARTUP 🔥")}")
      IO.puts("═══════════════════════════════════════════════════════════════")
      IO.puts("#{Themes.emitter_system_success_msg(pid, "  #{message}")}")
      
      # Add metadata details if available
      if components = Map.get(metadata, :components) do
        IO.puts("#{Themes.emitter_system_success_msg(pid, "  Components: #{components}")}")
      end
      if max_restarts = Map.get(metadata, :max_restarts) do
        IO.puts("#{Themes.emitter_system_success_msg(pid, "  Max Restarts: #{max_restarts}")}")
      end
      
      IO.puts("═══════════════════════════════════════════════════════════════")
      IO.puts("")
    end
    
    Logger.info("[EmitterSystem:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_shutdown_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      IO.puts("")
      IO.puts("═════════════════════════════════════════════════════════════")
      IO.puts("#{Themes.emitter_system_failure_msg(pid, "  🚨 EMITTER SYSTEM SHUTDOWN 🚨")}")
      IO.puts("═══════════════════════════════════════════════════════════════")
      IO.puts("#{Themes.emitter_system_failure_msg(pid, "  #{message}")}")
      
      if reason = Map.get(metadata, :reason) do
        IO.puts("#{Themes.emitter_system_failure_msg(pid, "  Reason: #{inspect(reason)}")}")
      end
      
      IO.puts("═══════════════════════════════════════════════════════════════")
      IO.puts("")
    end
    
    Logger.warning("[EmitterSystem:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_action_event(pid, message, metadata, state) do
    if state.terminal_output_enabled and state.logging_level in [:debug, :info] do
      IO.puts("#{Themes.emitter_system_action_msg(pid, "[EmitterSystem] #{message}")}")
    end
    
    Logger.info("[EmitterSystem:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_error_event(pid, message, metadata, state) do
    if state.terminal_output_enabled do
      IO.puts("#{Themes.emitter_system_failure_msg(pid, "[EmitterSystem:ERROR] #{message}")}")
    end
    
    Logger.error("[EmitterSystem:#{state.store_id}] #{message}", metadata)
  end
  
  defp handle_generic_event(event_type, pid, message, metadata, state) do
    if state.terminal_output_enabled and state.logging_level == :debug do
      IO.puts("#{Themes.emitter_system_action_msg(pid, "[EmitterSystem:#{event_type}] #{message}")}")
    end
    
    Logger.debug("[EmitterSystem:#{state.store_id}:#{event_type}] #{message}", metadata)
  end
end
