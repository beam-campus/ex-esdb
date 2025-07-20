defmodule ExESDB.LoggerFilters do
  @moduledoc """
  Custom logger filters to reduce noise from Ra, Khepri, and other verbose components
  """

  @doc """
  Filter Ra consensus library noise - only show errors and warnings
  """
  def filter_ra(log_event) do
    case log_event do
      {level, _gl, {Logger, msg, _ts, metadata}} ->
        if should_filter_ra?(level, msg, metadata) do
          :stop
        else
          :ignore
        end

      _ ->
        :ignore
    end
  end

  @doc """
  Filter Khepri noise - reduce verbose operational messages
  """
  def filter_khepri(log_event) do
    case log_event do
      {level, _gl, {Logger, msg, _ts, metadata}} ->
        if should_filter_khepri?(level, msg, metadata) do
          :stop
        else
          :ignore
        end

      _ ->
        :ignore
    end
  end

  @doc """
  Filter Swarm noise - already provided by BCUtils but adding our own
  """
  def filter_swarm(log_event) do
    case log_event do
      {level, _gl, {Logger, msg, _ts, metadata}} ->
        if should_filter_swarm?(level, msg, metadata) do
          :stop
        else
          :ignore
        end

      _ ->
        :ignore
    end
  end

  @doc """
  Filter libcluster noise - reduce cluster formation chatter
  """
  def filter_libcluster(log_event) do
    case log_event do
      {level, _gl, {Logger, msg, _ts, metadata}} ->
        if should_filter_libcluster?(level, msg, metadata) do
          :stop
        else
          :ignore
        end

      _ ->
        :ignore
    end
  end

  # Private functions for filtering logic

  defp should_filter_ra?(level, msg, metadata) do
    cond do
      # Always allow errors and warnings
      level in [:error, :warning] -> false
      
      # Filter Ra heartbeat and routine consensus messages
      ra_heartbeat_or_routine?(msg, metadata) -> true
      
      # Filter Ra state machine messages at info/debug level
      level in [:info, :debug] and ra_module?(metadata) -> true
      
      # Allow everything else
      true -> false
    end
  end

  defp should_filter_khepri?(level, msg, metadata) do
    cond do
      # Always allow errors and warnings
      level in [:error, :warning] -> false
      
      # Filter Khepri internal operations at info/debug level
      level in [:info, :debug] and khepri_module?(metadata) and khepri_routine?(msg) -> true
      
      # Allow everything else
      true -> false
    end
  end

  defp should_filter_swarm?(level, msg, metadata) do
    cond do
      # Always allow errors and warnings
      level in [:error, :warning] -> false
      
      # Filter Swarm routine operations
      level in [:info, :debug] and swarm_routine?(msg, metadata) -> true
      
      # Allow everything else
      true -> false
    end
  end

  defp should_filter_libcluster?(level, msg, metadata) do
    cond do
      # Always allow errors and warnings
      level in [:error, :warning] -> false
      
      # Filter libcluster connection attempts and gossip
      level in [:info, :debug] and libcluster_routine?(msg, metadata) -> true
      
      # Allow everything else
      true -> false
    end
  end

  # Helper functions to identify message types

  defp ra_heartbeat_or_routine?(msg, metadata) do
    msg_str = to_string(msg)
    
    cond do
      # Ra heartbeat messages
      String.contains?(msg_str, "heartbeat") -> true
      String.contains?(msg_str, "append_entries") -> true
      String.contains?(msg_str, "pre_vote") -> true
      String.contains?(msg_str, "request_vote") -> true
      
      # Ra state transitions (routine)
      String.contains?(msg_str, "follower") -> true
      String.contains?(msg_str, "candidate") -> true
      String.contains?(msg_str, "leader") and not String.contains?(msg_str, "election") -> true
      
      # Ra module metadata indicates internal operations
      ra_module?(metadata) -> true
      
      true -> false
    end
  end

  defp ra_module?(metadata) do
    case Keyword.get(metadata, :mfa) do
      {module, _, _} when is_atom(module) ->
        module_str = to_string(module)
        String.starts_with?(module_str, "Elixir.Ra") or 
        String.starts_with?(module_str, ":ra")
      _ -> false
    end
  end

  defp khepri_module?(metadata) do
    case Keyword.get(metadata, :mfa) do
      {module, _, _} when is_atom(module) ->
        module_str = to_string(module)
        String.starts_with?(module_str, "Elixir.Khepri") or 
        String.starts_with?(module_str, ":khepri")
      _ -> false
    end
  end

  defp khepri_routine?(msg) do
    msg_str = to_string(msg)
    
    # Filter routine Khepri operations
    String.contains?(msg_str, "cluster state") or
    String.contains?(msg_str, "store running") or
    String.contains?(msg_str, "cluster member")
  end

  defp swarm_routine?(msg, metadata) do
    msg_str = to_string(msg)
    
    # Filter routine Swarm operations
    String.contains?(msg_str, "registered") or
    String.contains?(msg_str, "unregistered") or
    String.contains?(msg_str, "nodeup") or
    String.contains?(msg_str, "nodedown") or
    swarm_module?(metadata)
  end

  defp swarm_module?(metadata) do
    case Keyword.get(metadata, :mfa) do
      {module, _, _} when is_atom(module) ->
        module_str = to_string(module)
        String.starts_with?(module_str, "Elixir.Swarm")
      _ -> false
    end
  end

  defp libcluster_routine?(msg, metadata) do
    msg_str = to_string(msg)
    
    # Filter routine libcluster operations
    String.contains?(msg_str, "connected to") or
    String.contains?(msg_str, "disconnected from") or
    String.contains?(msg_str, "gossip") or
    libcluster_module?(metadata)
  end

  defp libcluster_module?(metadata) do
    case Keyword.get(metadata, :mfa) do
      {module, _, _} when is_atom(module) ->
        module_str = to_string(module)
        String.starts_with?(module_str, "Elixir.Cluster")
      _ -> false
    end
  end
end
