defmodule ExESDB.LogFormatter do
  @moduledoc """
  Custom Logger formatter that preserves ExESDB's rich visual design.
  
  Supports three modes:
  - `:full` - Complete visual experience with colors and themed prefixes (default)
  - `:standard` - Clean output with emojis but no colors
  - `:minimal` - Production-ready minimal output
  
  ## Configuration
  
      # In config/dev.exs - Full visual experience
      config :logger, :console,
        format: {ExESDB.LogFormatter, :format},
        metadata: [:component, :pid, :indent, :visual, :arrow]
      
      # In config/prod.exs - Minimal output
      config :logger, :console,
        format: {ExESDB.LogFormatter, :format},
        metadata: [:component],
        colors: [enabled: false]
      
      config :ex_esdb, :visual_mode, :minimal
  
  ## Usage
  
      Logger.info("🚀 ACTIVATING LEADERSHIP RESPONSIBILITIES",
        component: :leader_worker,
        pid: self(),
        arrow: true
      )
  """
  
  
  @doc """
  Format log messages according to the configured visual mode.
  """
  def format(level, message, timestamp, metadata) do
    visual_mode = Application.get_env(:ex_esdb, :visual_mode, :full)
    
    case visual_mode do
      :full -> format_visual(level, message, timestamp, metadata)
      :standard -> format_standard(level, message, timestamp, metadata)
      :minimal -> format_minimal(level, message, timestamp, metadata)
    end
  end
  
  # Full visual mode - recreate the original themed output
  defp format_visual(_level, message, _timestamp, metadata) do
    component = Keyword.get(metadata, :component)
    pid = Keyword.get(metadata, :pid)
    indent = Keyword.get(metadata, :indent, 0)
    arrow = Keyword.get(metadata, :arrow, false)
    
    # Get the themed prefix if component is specified
    prefix = if component && pid do
      try do
        apply(Themes, component, [pid])
      rescue
        _ -> format_fallback_prefix(component, pid)
      end
    else
      ""
    end
    
    # Handle arrow formatting for main events
    message_with_arrow = if arrow do
      " ==> #{message}"
    else
      message
    end
    
    # Apply indentation
    indentation = String.duplicate("  ", indent)
    formatted_message = if indent > 0 do
      "#{indentation}#{message_with_arrow}"
    else
      "#{prefix}#{message_with_arrow}"
    end
    
    # Add newline for better visual separation
    "#{formatted_message}\n"
  end
  
  # Standard mode - no colors but keep structure and emojis
  defp format_standard(level, message, timestamp, metadata) do
    component = Keyword.get(metadata, :component)
    pid = Keyword.get(metadata, :pid)
    indent = Keyword.get(metadata, :indent, 0)
    arrow = Keyword.get(metadata, :arrow, false)
    
    # Simple prefix without colors
    prefix = if component && pid do
      "[#{format_component_name(component)} #{inspect(pid)}]"
    else
      ""
    end
    
    # Handle arrow formatting
    message_with_arrow = if arrow do
      " ==> #{message}"
    else
      message
    end
    
    # Apply indentation
    indentation = String.duplicate("  ", indent)
    formatted_message = if indent > 0 do
      "#{indentation}#{message_with_arrow}"
    else
      "#{prefix}#{message_with_arrow}"
    end
    
    # Include timestamp and level in standard mode
    time = format_time(timestamp)
    "[#{time}] [#{level}]#{formatted_message}\n"
  end
  
  # Minimal mode - production-ready output
  defp format_minimal(level, message, timestamp, metadata) do
    component = Keyword.get(metadata, :component)
    
    # Strip emojis for minimal mode
    clean_message = strip_emojis(message)
    
    # Simple component prefix if specified
    prefix = if component do
      "[#{format_component_name(component)}]"
    else
      ""
    end
    
    time = format_time(timestamp)
    "[#{time}] [#{level}]#{prefix} #{clean_message}\n"
  end
  
  # Helper to format component names consistently
  defp format_component_name(component) do
    component
    |> to_string()
    |> String.upcase()
    |> String.replace("_", " ")
  end
  
  # Fallback prefix formatting when Themes function doesn't exist
  defp format_fallback_prefix(component, pid) do
    "[#{format_component_name(component)} #{inspect(pid)}]"
  end
  
  # Format timestamp
  defp format_time({date, {hour, minute, second, _millisecond}}) do
    {:ok, datetime} = NaiveDateTime.new(date, {hour, minute, second})
    Calendar.strftime(datetime, "%H:%M:%S")
  end
  
  # Strip emoji characters for minimal mode
  defp strip_emojis(message) do
    # Remove common emojis used in ExESDB
    message
    |> String.replace(~r/[🏆🚀📊📝✅❌🔄⚠️🔴🟢📞🔻⚙️🥈🧹🟠]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end