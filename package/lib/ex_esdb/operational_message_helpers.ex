defmodule ExESDB.OperationalMessageHelpers do
  @moduledoc """
  Common utilities for ExESDB operational message creation and handling.

  This module provides consistent patterns for operational/system messages to ensure
  compatibility with ExESDBGater messaging patterns. This is SEPARATE from application
  domain events that flow through :ex_esdb_events.

  ## Scope

  This module handles operational messages for:
  - System lifecycle and configuration (`:ex_esdb_system`)
  - Health monitoring (`:ex_esdb_health`) 
  - Performance metrics (`:ex_esdb_metrics`)
  - Security events (`:ex_esdb_security`)
  - Audit trail (`:ex_esdb_audit`)
  - Critical alerts (`:ex_esdb_alerts`)
  - Diagnostic information (`:ex_esdb_diagnostics`)
  - Process lifecycle (`:ex_esdb_lifecycle`)
  - Log aggregation (`:ex_esdb_logging`)

  ## Node Field Guidelines

  All operational message structs should include node tracking:
  - `:node` - for general operational events originating on a node
  - `:source_node` - for ExESDB-specific events where source context is important
  - `:originating_node` - for cluster events where distinction is needed from affected nodes

  ## Integration with ExESDBGater

  This module ensures ExESDB operational messages are compatible with ExESDBGater
  message formats, enabling seamless integration between the two systems.

  ## Usage

      # Create operational health message
      health_payload = OperationalMessageHelpers.create_health_message(
        :store_worker, :healthy, %{store_id: :main_store}
      )

      # Create system lifecycle message  
      lifecycle_payload = OperationalMessageHelpers.create_system_lifecycle(
        :started, :ex_esdb, version
      )
  """

  @doc """
  Returns the current timestamp with millisecond precision in UTC.
  
  This ensures consistent timestamp formatting across all operational message types
  and maintains compatibility with ExESDBGater messaging patterns.
  """
  def current_timestamp do
    DateTime.utc_now() |> DateTime.truncate(:millisecond)
  end

  @doc """
  Gets the node value from options, defaulting to Node.self().
  
  ## Examples
  
      iex> OperationalMessageHelpers.get_node([])
      :"node@hostname"
      
      iex> OperationalMessageHelpers.get_node([node: :test_node])
      :test_node
  """
  def get_node(opts \\ []) do
    Keyword.get(opts, :node, Node.self())
  end

  @doc """
  Gets the source_node value from options, defaulting to Node.self().
  
  Used for ExESDB-specific operational events where source context is important.
  """
  def get_source_node(opts \\ []) do
    Keyword.get(opts, :source_node, Node.self())
  end

  @doc """
  Gets the originating_node value from options, defaulting to Node.self().
  
  Used for cluster operational events where the originating node
  needs to be distinguished from affected nodes.
  """
  def get_originating_node(opts \\ []) do
    Keyword.get(opts, :originating_node, Node.self())
  end

  @doc """
  Validates that an operational message has all required fields.
  """
  def validate_operational_fields(message, required_fields) when is_list(required_fields) do
    message_map = if is_struct(message), do: Map.from_struct(message), else: message
    
    missing_fields = 
      required_fields
      |> Enum.filter(fn field ->
        case Map.get(message_map, field) do
          nil -> true
          _ -> false
        end
      end)
    
    case missing_fields do
      [] -> {:ok, message}
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  @doc """
  Validates that all node-related fields in an operational message are atoms.
  """
  def validate_node_fields(message) do
    node_fields = [:node, :source_node, :originating_node]
    message_map = if is_struct(message), do: Map.from_struct(message), else: message
    
    invalid_fields = 
      node_fields
      |> Enum.filter(fn field ->
        case Map.get(message_map, field) do
          nil -> false  # Missing fields are ok
          value when is_atom(value) -> false  # Valid
          _ -> true  # Invalid (not an atom)
        end
      end)
    
    case invalid_fields do
      [] -> :ok
      fields -> {:error, {:invalid_node_fields, fields}}
    end
  end

  @doc """
  Extracts ExESDB cluster context information for enhanced operational message tracking.
  
  This provides additional context that can be useful for debugging
  and monitoring ExESDB cluster operations.
  """
  def cluster_context do
    connected_nodes = Node.list()
    
    %{
      node_name: Node.self(),
      connected_nodes: connected_nodes,
      cluster_size: length(connected_nodes) + 1,
      node_type: determine_node_type()
    }
  end

  @doc """
  Creates a unique identifier for operational messages that need tracking.
  """
  def generate_operational_id(prefix \\ "op") do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
    "#{prefix}_#{timestamp}_#{random}"
  end

  @doc """
  Creates ExESDBGater-compatible health message payload.
  
  This bridges ExESDB health information to ExESDBGater HealthMessages format.
  """
  def create_health_message(component, status, details \\ %{}, opts \\ []) do
    case Code.ensure_loaded?(ExESDBGater.Messages.HealthMessages) do
      {:module, _} ->
        case ExESDBGater.Messages.HealthMessages.component_health(component, get_node(opts), status) do
          %{} = payload -> payload
          _ -> create_native_health_message(component, status, details, opts)
        end
      _ ->
        create_native_health_message(component, status, details, opts)
    end
  end

  @doc """
  Creates ExESDBGater-compatible system lifecycle message payload.
  """
  def create_system_lifecycle(event, system_name, version, opts \\ []) do
    case Code.ensure_loaded?(ExESDBGater.Messages.SystemMessages) do
      {:module, _} ->
        # Use the proper helper function to create the struct
        ExESDBGater.Messages.SystemMessages.system_lifecycle(event, system_name, version, opts)
      _ ->
        create_native_system_lifecycle(event, system_name, version, opts)
    end
  end

  @doc """
  Creates ExESDBGater-compatible metrics message payload.
  """
  def create_metrics_message(component, metrics_data, opts \\ []) do
    case Code.ensure_loaded?(ExESDBGater.Messages.MetricsMessages) do
      {:module, _} ->
        create_gater_metrics_message(component, metrics_data, opts)
      _ ->
        create_native_metrics_message(component, metrics_data, opts)
    end
  end
  
  defp create_gater_metrics_message(component, metrics_data, opts) when component in [:persistence, :store] do
    case ExESDBGater.Messages.MetricsMessages.performance_metric(
      :persistence_operation,
      Map.get(metrics_data, :value, 0),
      Map.get(metrics_data, :unit, "operations")
    ) do
      %{} = payload -> Map.merge(payload, %{node: get_node(opts), timestamp: current_timestamp()})
      _ -> create_native_metrics_message(component, metrics_data, opts)
    end
  end
  
  defp create_gater_metrics_message(component, metrics_data, opts) when component in [:emitter, :subscription] do
    case ExESDBGater.Messages.MetricsMessages.throughput_metric(
      :event_processing,
      Map.get(metrics_data, :count, 0),
      Map.get(metrics_data, :duration_ms, 1000)
    ) do
      %{} = payload -> Map.merge(payload, %{node: get_node(opts), timestamp: current_timestamp()})
      _ -> create_native_metrics_message(component, metrics_data, opts)
    end
  end
  
  defp create_gater_metrics_message(component, metrics_data, opts) do
    case ExESDBGater.Messages.MetricsMessages.performance_metric(
      component,
      Map.get(metrics_data, :value, 0),
      Map.get(metrics_data, :unit, "count")
    ) do
      %{} = payload -> Map.merge(payload, %{node: get_node(opts), timestamp: current_timestamp()})
      _ -> create_native_metrics_message(component, metrics_data, opts)
    end
  end

  @doc """
  Creates ExESDBGater-compatible alert message payload.
  """
  def create_alert_message(severity, category, title, description, opts \\ []) do
    case Code.ensure_loaded?(ExESDBGater.Messages.AlertMessages) do
      {:module, _} ->
        case ExESDBGater.Messages.AlertMessages.system_alert(severity, category, title, description, "ExESDB") do
          %{} = payload -> Map.merge(payload, %{node: get_node(opts), timestamp: current_timestamp()})
          _ -> create_native_alert_message(severity, category, title, description, opts)
        end
      _ ->
        create_native_alert_message(severity, category, title, description, opts)
    end
  end

  @doc """
  Common validation for operational messages.
  
  Ensures messages follow both ExESDB and ExESDBGater compatibility requirements.
  """
  def validate_operational_message(message, required_fields) do
    with {:ok, _} <- validate_operational_fields(message, required_fields ++ [:timestamp]),
         :ok <- validate_node_fields(message),
         :ok <- validate_timestamp_field(message) do
      {:ok, message}
    end
  end

  # Private functions

  defp determine_node_type do
    applications = Application.loaded_applications() |> Enum.map(&elem(&1, 0))
    
    cond do
      :ex_esdb in applications and :ex_esdb_gater in applications -> :combined_node
      :ex_esdb in applications -> :ex_esdb_node
      :ex_esdb_gater in applications -> :gater_node
      true -> :unknown
    end
  end

  defp create_native_health_message(component, status, details, opts) do
    %{
      component: component,
      node: get_node(opts),
      status: status,
      details: details,
      timestamp: current_timestamp()
    }
  end

  defp create_native_system_lifecycle(event, system_name, version, opts) do
    %{
      event: event,
      system_name: system_name,
      version: version,
      node: get_node(opts),
      timestamp: current_timestamp()
    }
  end

  defp create_native_metrics_message(component, metrics_data, opts) do
    %{
      component: component,
      metrics: metrics_data,
      node: get_node(opts),
      timestamp: current_timestamp()
    }
  end

  defp create_native_alert_message(severity, category, title, description, opts) do
    %{
      severity: severity,
      category: category,
      title: title,
      description: description,
      source: "ExESDB",
      node: get_node(opts),
      timestamp: current_timestamp()
    }
  end

  defp validate_timestamp_field(message) do
    message_map = if is_struct(message), do: Map.from_struct(message), else: message
    
    case Map.get(message_map, :timestamp) do
      %DateTime{} -> :ok
      nil -> {:error, {:missing_fields, [:timestamp]}}
      _ -> {:error, {:invalid_timestamp, :not_datetime}}
    end
  end
end
