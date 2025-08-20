defmodule ExESDB.PubSubIntegration do
  @moduledoc """
  Helper module for consistent pubsub integration across ExESDB modules.
  
  This module provides standardized functions for broadcasting events to the
  ExESDBGater pubsub system, with built-in error handling and optional
  enablement/disablement of pubsub features.
  
  This module now uses ExESDB.OperationalMessageHelpers to ensure consistent
  node tracking fields, millisecond-precision timestamps, and message validation
  across all operational message types.
  
  ## Configuration
  
  Add to your config to enable pubsub integration:
  
      config :ex_esdb,
        pubsub_integration: true,
        health_broadcast_interval: 30_000,
        metrics_broadcast_interval: 60_000
  
  ## Usage Examples
  
      # System lifecycle events with standardized nodes and timestamps
      ExESDB.PubSubIntegration.broadcast_system_lifecycle(:started, :ex_esdb, "1.0.0")
      
      # Health updates with consistent node tracking
      ExESDB.PubSubIntegration.broadcast_health_update(:store_worker, :healthy, %{store_id: "main"})
      
      # Metrics with precise timestamps
      ExESDB.PubSubIntegration.broadcast_metrics(:persistence, %{operations: 100, errors: 0})
      
      # Alerts with ExESDBGater compatibility
      ExESDB.PubSubIntegration.broadcast_alert(:node_failure, :critical, "Node down", %{node: :node1})
  """
  
  alias ExESDB.OperationalMessageHelpers
  alias ExESDBGater.Messages.{
    SystemMessages, HealthMessages, MetricsMessages,
    LifecycleMessages, AlertMessages, AuditMessages,
    DiagnosticsMessages, SecurityMessages, LoggingMessages
  }
  
  require Logger
  
  ## System Lifecycle Events
  
  @doc """
  Broadcast system lifecycle events (startup, shutdown, config changes).
  """
  def broadcast_system_lifecycle(event, system_name, version, opts \\ []) do
    case enabled?() do
      false -> :disabled
      true -> do_broadcast_system_lifecycle(event, system_name, version, opts)
    end
  end
  
  defp do_broadcast_system_lifecycle(event, system_name, version, opts) do
    topic = Keyword.get(opts, :topic, "lifecycle")
    payload = build_system_lifecycle_payload(event, system_name, version, opts)
    broadcast_system_lifecycle_message(topic, payload)
  end
  
  defp broadcast_system_lifecycle_message(topic, {:ok, payload}) do
    case SystemMessages.broadcast_system_lifecycle(topic, payload) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> log_and_return_error("system lifecycle event", reason)
    end
  end
  
  defp broadcast_system_lifecycle_message(_topic, {:error, reason}) do
    log_and_return_error("system lifecycle event", reason)
  end
  
  @doc """
  Broadcast system configuration changes.
  """
  def broadcast_system_config(component, changes, opts \\ []) do
    case enabled?() do
      false -> :disabled
      true -> do_broadcast_system_config(component, changes, opts)
    end
  end
  
  defp do_broadcast_system_config(component, changes, opts) do
    topic = Keyword.get(opts, :topic, "config")
    payload = build_system_config_payload(component, changes, opts)
    broadcast_system_config_message(topic, payload)
  end
  
  defp broadcast_system_config_message(topic, {:ok, payload}) do
    case SystemMessages.broadcast_system_config(topic, payload) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> log_and_return_error("system config change", reason)
    end
  end
  
  defp broadcast_system_config_message(_topic, {:error, reason}) do
    log_and_return_error("system config change", reason)
  end
  
  ## Health Events
  
  @doc """
  Broadcast store-specific component health updates using store_id for topic generation.
  """
  def broadcast_store_health(store_id, component, status, details \\ %{}, opts \\ []) when is_atom(store_id) do
    case enabled?() do
      false -> :disabled
      true -> do_broadcast_store_health(store_id, component, status, details, opts)
    end
  end
  
  defp do_broadcast_store_health(store_id, component, status, details, opts) do
    topic = HealthMessages.store_health_topic(store_id)
    payload = build_health_payload(component, status, Map.put(details, :store_id, store_id), opts)
    broadcast_store_health_message(store_id, topic, payload)
  end
  
  defp broadcast_store_health_message(store_id, topic, {:ok, payload}) do
    case HealthMessages.broadcast_store_health(topic, payload) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> log_and_return_error("store health update", reason)
    end
  end
  
  defp broadcast_store_health_message(_store_id, _topic, {:error, reason}) do
    log_and_return_error("store health update", reason)
  end
  
  @doc """
  Broadcast cluster-wide health status.
  """
  def broadcast_cluster_health(nodes, failed_nodes, event_type, opts \\ []) do
    case enabled?() do
      false -> :disabled
      true -> do_broadcast_cluster_health(nodes, failed_nodes, event_type, opts)
    end
  end
  
  defp do_broadcast_cluster_health(nodes, failed_nodes, event_type, opts) do
    topic = HealthMessages.cluster_health_topic()
    payload = build_cluster_health_payload(nodes, failed_nodes, event_type, opts)
    broadcast_cluster_health_message(topic, payload)
  end
  
  defp broadcast_cluster_health_message(topic, {:ok, payload}) do
    case HealthMessages.broadcast_cluster_health_update(payload) do
      {:ok, _} -> :ok
      {:error, reason} -> log_and_return_error("cluster health", reason)
    end
  end
  
  defp broadcast_cluster_health_message(_topic, {:error, reason}) do
    log_and_return_error("cluster health", reason)
  end
  
  @doc """
  Legacy function for backward compatibility - broadcasts to component_health topic.
  """
  def broadcast_health_update(component, status, details \\ %{}, opts \\ []) do
    case enabled?() do
      false -> :disabled
      true -> do_broadcast_health_update(component, status, details, opts)
    end
  end
  
  defp do_broadcast_health_update(component, status, details, opts) do
    topic = Keyword.get(opts, :topic, "component_health")
    payload = build_health_payload(component, status, details, opts)
    broadcast_health_update_message(topic, payload)
  end
  
  defp broadcast_health_update_message(topic, {:ok, payload}) do
    case HealthMessages.broadcast_node_health(topic, payload) do
      {:ok, _} -> :ok
      {:error, reason} -> log_and_return_error("health update", reason)
    end
  end
  
  defp broadcast_health_update_message(_topic, {:error, reason}) do
    log_and_return_error("health update", reason)
  end
  
  
  ## Metrics Events
  
  @doc """
  Broadcast component performance metrics.
  """
  def broadcast_metrics(component, metrics, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, payload} <- build_metrics_payload(component, metrics, opts),
         topic <- Keyword.get(opts, :topic, to_string(component)),
         {:ok, _} <- broadcast_metrics_by_component(component, topic, payload) do
      :ok
    else
      :disabled -> :disabled
      {:error, reason} -> log_and_return_error("metrics for #{component}", reason)
    end
  end
  
  ## Alert Events
  
  @doc """
  Broadcast critical alerts and notifications.
  """
  def broadcast_alert(alert_type, severity, message, context \\ %{}, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, payload} <- build_alert_payload(alert_type, severity, message, context, opts),
         topic <- Keyword.get(opts, :topic, to_string(alert_type)),
         {:ok, _} <- broadcast_alert_by_type(alert_type, topic, payload) do
      :ok
    else
      :disabled -> :disabled
      {:error, reason} -> log_and_return_error("alert", reason)
    end
  end
  
  ## Audit Events
  
  @doc """
  Broadcast audit trail events for compliance and tracking.
  """
  def broadcast_audit_event(event_type, actor, resource, action, details \\ %{}, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, payload} <- build_audit_payload(event_type, actor, resource, action, details, opts),
         topic <- Keyword.get(opts, :topic, to_string(event_type)),
         {:ok, _} <- broadcast_audit_by_type(event_type, topic, payload) do
      :ok
    else
      :disabled -> :disabled
      {:error, reason} -> log_and_return_error("audit event", reason)
    end
  end
  
  ## Lifecycle Events
  
  @doc """
  Broadcast process and node lifecycle events.
  """
  def broadcast_lifecycle_event(event_type, process_name, details \\ %{}, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, payload} <- build_lifecycle_payload(event_type, process_name, details, opts),
         topic <- Keyword.get(opts, :topic, "process_lifecycle"),
         result <- LifecycleMessages.broadcast_process_lifecycle(topic, payload) do
      case result do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, reason} -> log_and_return_error("lifecycle event", reason)
      end
    else
      :disabled -> :disabled
      {:error, reason} -> log_and_return_error("lifecycle event", reason)
    end
  end
  
  ## Diagnostic Events
  
  @doc """
  Broadcast diagnostic information for debugging and troubleshooting.
  """
  def broadcast_diagnostic(diagnostic_type, component, data, opts \\ []) do
    with :ok <- check_enabled(),
         {:ok, payload} <- build_diagnostic_payload(component, diagnostic_type, data, opts),
         topic <- Keyword.get(opts, :topic, "diagnostics"),
         result <- DiagnosticsMessages.broadcast_debug_trace(topic, payload) do
      case result do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, reason} -> log_and_return_error("diagnostic", reason)
      end
    else
      :disabled -> :disabled
      {:error, reason} -> log_and_return_error("diagnostic", reason)
    end
  end
  
  ## Configuration and Utilities
  
  @doc """
  Check if pubsub integration is enabled.
  """
  def enabled? do
    # Re-enabled for dashboard integration
    Application.get_env(:ex_esdb, :pubsub_integration, false)
  end
  
  @doc """
  Validate messaging compatibility between ExESDB and ExESDBGater.
  
  This function tests that operational messages can be created and validated
  using both systems' message patterns.
  """
  def validate_messaging_compatibility do
    %{
      operational_helpers: validate_operational_helpers(),
      gater_integration: validate_gater_message_integration(),
      node_consistency: validate_node_field_consistency(),
      timestamp_precision: validate_timestamp_precision()
    }
  end
  
  @doc """
  Get the configured health broadcast interval.
  """
  def health_broadcast_interval do
    Application.get_env(:ex_esdb, :health_broadcast_interval, 30_000)
  end
  
  @doc """
  Get the configured metrics broadcast interval.
  """
  def metrics_broadcast_interval do
    Application.get_env(:ex_esdb, :metrics_broadcast_interval, 60_000)
  end
  
  @doc """
  Enable pubsub integration at runtime.
  """
  def enable! do
    Application.put_env(:ex_esdb, :pubsub_integration, true)
  end
  
  @doc """
  Disable pubsub integration at runtime.
  """
  def disable! do
    Application.put_env(:ex_esdb, :pubsub_integration, false)
  end
  
  ## Batch Operations
  
  @doc """
  Broadcast multiple events in a batch for efficiency.
  """
  def broadcast_batch(events, opts \\ []) do
    case check_enabled() do
      :ok ->
        results = Enum.map(events, &process_batch_event(&1, opts))
        analyze_batch_results(results)
      :disabled ->
        {:ok, %{success: 0, errors: 0, disabled: true}}
    end
  end
  
  ## Private Helper Functions
  
  defp check_enabled(), do: do_check_enabled(enabled?())
  
  defp do_check_enabled(true), do: :ok
  defp do_check_enabled(_), do: :disabled
  
  defp log_and_return_error(operation, reason) do
    Logger.warning("Failed to broadcast #{operation}: #{inspect(reason)}")
    {:error, reason}
  end
  
  # Payload builders - now using OperationalMessageHelpers for consistency
  
  defp build_system_lifecycle_payload(event, system_name, version, opts) do
    payload = SystemMessages.system_lifecycle(event, system_name, version, opts)
    validate_system_lifecycle_payload(payload)
  end
  
  defp validate_system_lifecycle_payload(%SystemMessages.SystemLifecycle{} = payload), do: {:ok, payload}
  defp validate_system_lifecycle_payload(payload) when is_map(payload), do: {:ok, payload}
  defp validate_system_lifecycle_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_system_config_payload(component, changes, opts) do
    config_opts = [
      previous_config: Keyword.get(opts, :previous_config),
      changed_by: Keyword.get(opts, :changed_by, "system"),
      node: Keyword.get(opts, :node, Node.self()),
      timestamp: DateTime.utc_now()
    ]
    
    payload = SystemMessages.system_config(component, changes, config_opts)
    validate_system_config_payload(payload)
  end
  
  defp validate_system_config_payload(%SystemMessages.SystemConfig{} = payload), do: {:ok, payload}
  defp validate_system_config_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_health_payload(component, status, details, opts) do
    # Create payload using ExESDBGater HealthMessages directly
    node = OperationalMessageHelpers.get_node(opts)
    timestamp = OperationalMessageHelpers.current_timestamp()
    
    # Use HealthMessages to create the proper structure
    # Convert details map to keyword list since component_health/4 expects a keyword list
    details_list = Enum.into(details, [])
    payload = HealthMessages.component_health(component, node, status, details_list)
    {:ok, payload}
  end
  
  defp validate_health_payload(%HealthMessages.ComponentHealth{} = payload), do: {:ok, payload}
  defp validate_health_payload(%HealthMessages.NodeHealth{} = payload), do: {:ok, payload}
  defp validate_health_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_cluster_health_payload(nodes, failed_nodes, event_type, opts) do
    cluster_opts = [
      originating_node: OperationalMessageHelpers.get_originating_node(opts),
      timestamp: OperationalMessageHelpers.current_timestamp()
    ] ++ opts
    
    payload = HealthMessages.cluster_health(nodes, failed_nodes, event_type, cluster_opts)
    validate_cluster_health_payload(payload)
  end
  
  defp validate_cluster_health_payload(%HealthMessages.ClusterHealth{} = payload), do: {:ok, payload}
  defp validate_cluster_health_payload(error), do: {:error, {:invalid_payload, error}}
  
  
  defp build_metrics_payload(component, metrics, opts) do
    # Always use component-specific metrics building to ensure proper struct creation
    build_component_specific_metrics(component, metrics, opts)
  end
  
  defp validate_metrics_payload(%MetricsMessages.PerformanceMetric{} = payload), do: {:ok, payload}
  defp validate_metrics_payload(%MetricsMessages.ThroughputMetric{} = payload), do: {:ok, payload}
  defp validate_metrics_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_legacy_metrics_payload(component, metrics, opts) do
    {:ok, payload} = build_component_specific_metrics(component, metrics, opts)
    {:ok, payload}
  end
  
  defp build_component_specific_metrics(:persistence, metrics, opts) do
    metric_opts = [
      component: :persistence,
      node: OperationalMessageHelpers.get_node(opts),
      timestamp: OperationalMessageHelpers.current_timestamp(),
      tags: %{
        stores_count: Map.get(metrics, :stores_count, 0),
        duration_ms: Map.get(metrics, :duration_ms, 0),
        success_count: Map.get(metrics, :success_count, 0),
        error_count: Map.get(metrics, :error_count, 0)
      }
    ] ++ opts
    
    payload = MetricsMessages.performance_metric(
      :persistence_operation,
      Map.get(metrics, :operations_count, 0),
      "operations",
      metric_opts
    )
    {:ok, payload}
  end
  
  defp build_component_specific_metrics(:emitter, metrics, opts) do
    duration_ms = Map.get(metrics, :duration_ms, 1000)
    events_emitted = Map.get(metrics, :events_emitted, 0)
    
    metric_opts = [
      node: OperationalMessageHelpers.get_node(opts),
      timestamp: OperationalMessageHelpers.current_timestamp()
    ] ++ opts
    
    payload = MetricsMessages.throughput_metric(
      :event_emission,
      events_emitted,
      duration_ms,
      metric_opts
    )
    {:ok, payload}
  end
  
  defp build_component_specific_metrics(component, metrics, opts) do
    metric_opts = [
      component: component,
      node: OperationalMessageHelpers.get_node(opts),
      timestamp: OperationalMessageHelpers.current_timestamp(),
      tags: metrics
    ] ++ opts
    
    payload = MetricsMessages.performance_metric(
      component,
      Map.get(metrics, :value, 0),
      Map.get(metrics, :unit, "count"),
      metric_opts
    )
    {:ok, payload}
  end
  
  defp build_alert_payload(alert_type, severity, message, context, opts) do
    payload = OperationalMessageHelpers.create_alert_message(alert_type, severity, message, context, opts)
    validate_alert_payload(payload)
  end
  
  defp validate_alert_payload(%AlertMessages.SystemAlert{} = payload), do: {:ok, payload}
  defp validate_alert_payload(payload) when is_map(payload), do: {:ok, payload}
  defp validate_alert_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_audit_payload(event_type, actor, resource, action, details, opts) do
    payload = build_audit_event(event_type, actor, resource, action, details, opts)
    validate_audit_payload(payload)
  end
  
  defp validate_audit_payload(%AuditMessages.DataChange{} = payload), do: {:ok, payload}
  defp validate_audit_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_audit_event(_event_type, actor, resource, action, details, opts) do
    enriched_details = %{
      details: details, 
      timestamp: OperationalMessageHelpers.current_timestamp(),
      node: OperationalMessageHelpers.get_node(opts)
    }
    
    AuditMessages.data_change(actor, action, resource, enriched_details)
  end
  
  defp build_lifecycle_payload(event_type, process_name, details, opts) do
    node = OperationalMessageHelpers.get_node(opts)
    
    # Extract component to determine the module
    component = Map.get(details, :component, :unknown)
    module_name = case component do
      :persistence_worker -> ExESDB.PersistenceWorker
      :emitter_worker -> ExESDB.EmitterWorker
      :core_system -> ExESDB.CoreSystem
      _ -> component
    end
    
    # Convert details map to keyword list for LifecycleMessages.process_lifecycle/4
    lifecycle_opts = [
      name: process_name,
      reason: Map.get(details, :reason),
      restart_count: Map.get(details, :restart_count, 0),
      node: node
    ] ++ opts
    
    # LifecycleMessages.process_lifecycle expects: pid, module, event, opts
    # Use process_name as pid since we don't have the actual pid in this context
    payload = LifecycleMessages.process_lifecycle(process_name, module_name, event_type, lifecycle_opts)
    validate_lifecycle_payload(payload)
  end
  
  defp validate_lifecycle_payload(%LifecycleMessages.ProcessLifecycle{} = payload), do: {:ok, payload}
  defp validate_lifecycle_payload(error), do: {:error, {:invalid_payload, error}}
  
  defp build_diagnostic_payload(component, diagnostic_type, data, opts) do
    enriched_data = Map.merge(data, %{
      node: OperationalMessageHelpers.get_node(opts),
      timestamp: OperationalMessageHelpers.current_timestamp()
    })
    
    payload = DiagnosticsMessages.debug_trace(component, diagnostic_type, enriched_data)
    validate_diagnostic_payload(payload)
  end
  
  defp validate_diagnostic_payload(%DiagnosticsMessages.DebugTrace{} = payload), do: {:ok, payload}
  defp validate_diagnostic_payload(error), do: {:error, {:invalid_payload, error}}
  
  # Broadcasting helpers
  
  defp broadcast_metrics_by_component(:persistence, topic, %MetricsMessages.PerformanceMetric{} = payload) do
    case MetricsMessages.broadcast_performance_metric(topic, payload) do
      :ok -> {:ok, :broadcasted}
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp broadcast_metrics_by_component(:emitter, topic, %MetricsMessages.ThroughputMetric{} = payload) do
    case MetricsMessages.broadcast_throughput_metric(topic, payload) do
      :ok -> {:ok, :broadcasted}
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp broadcast_metrics_by_component(_, topic, %MetricsMessages.PerformanceMetric{} = payload) do
    case MetricsMessages.broadcast_performance_metric(topic, payload) do
      :ok -> {:ok, :broadcasted}
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp broadcast_alert_by_type(_, topic, %AlertMessages.SystemAlert{} = payload) do
    AlertMessages.broadcast_system_alert(topic, payload)
  end
  
  defp broadcast_audit_by_type(_, topic, %AuditMessages.DataChange{} = payload) do
    AuditMessages.broadcast_data_change(topic, payload)
  end
  
  # Batch processing helpers
  
  defp process_batch_event(event, opts) do
    case event do
      {:system_lifecycle, event, system_name, version} ->
        broadcast_system_lifecycle(event, system_name, version, opts)
      {:health_update, component, status, details} ->
        broadcast_health_update(component, status, details, opts)
      {:metrics, component, metrics} ->
        broadcast_metrics(component, metrics, opts)
      {:alert, alert_type, severity, message, context} ->
        broadcast_alert(alert_type, severity, message, context, opts)
      _ ->
        {:error, :unknown_event_type}
    end
  end
  
  defp analyze_batch_results(results) do
    success_count = Enum.count(results, &(&1 == :ok or &1 == :disabled))
    error_count = Enum.count(results, &(match?({:error, _}, &1) or &1 == :error))
    
    if error_count > 0 do
      Logger.warning("Batch broadcast: #{success_count} succeeded, #{error_count} failed")
    end
    
    {:ok, %{success: success_count, errors: error_count}}
  end
  
  # Messaging compatibility validation helpers
  
  defp validate_operational_helpers do
    test_node = OperationalMessageHelpers.get_node([])
    test_timestamp = OperationalMessageHelpers.current_timestamp()
    
    %{
      node_helper: is_atom(test_node),
      timestamp_helper: %DateTime{} = test_timestamp,
      cluster_context: is_map(OperationalMessageHelpers.cluster_context())
    }
  rescue
    error -> {:error, {:operational_helpers_failure, error}}
  end
  
  defp validate_gater_message_integration do
    gater_available = Code.ensure_loaded?(ExESDBGater.Messages.SystemMessages)
    
    test_results = if gater_available do
      %{
        system_messages: test_system_message_creation(),
        health_messages: test_health_message_creation(),
        metrics_messages: test_metrics_message_creation()
      }
    else
      %{gater_not_loaded: true}
    end
    
    %{gater_available: gater_available, tests: test_results}
  rescue
    error -> {:error, {:gater_integration_failure, error}}
  end
  
  defp validate_node_field_consistency do
    test_opts = [node: :test_node]
    system_payload = build_system_lifecycle_payload(:test, :ex_esdb, "0.0.1", test_opts)
    health_payload = build_health_payload(:test_component, :healthy, %{}, test_opts)
    
    %{
      system_has_node: payload_has_node_field?(system_payload),
      health_has_node: payload_has_node_field?(health_payload)
    }
  rescue
    error -> {:error, {:node_consistency_failure, error}}
  end
  
  defp validate_timestamp_precision do
    timestamp1 = OperationalMessageHelpers.current_timestamp()
    :timer.sleep(1)  # Ensure different timestamps
    timestamp2 = OperationalMessageHelpers.current_timestamp()
    
    %{
      datetime_format: %DateTime{} = timestamp1,
      has_precision: timestamp1 != timestamp2,
      millisecond_truncated: timestamp1.microsecond != nil
    }
  rescue
    error -> {:error, {:timestamp_precision_failure, error}}
  end
  
  defp test_system_message_creation do
    OperationalMessageHelpers.create_system_lifecycle(:started, :ex_esdb, "1.0.0")
    :ok
  rescue
    _ -> :error
  end
  
  defp test_health_message_creation do
    OperationalMessageHelpers.create_health_message(:test_component, :healthy)
    :ok
  rescue
    _ -> :error
  end
  
  defp test_metrics_message_creation do
    OperationalMessageHelpers.create_metrics_message(:persistence, %{value: 100})
    :ok
  rescue
    _ -> :error
  end
  
  defp payload_has_node_field?({:ok, payload}) when is_map(payload) do
    has_node_key = Map.has_key?(payload, :node)
    has_source_node_key = Map.has_key?(payload, :source_node)
    has_originating_node_key = Map.has_key?(payload, :originating_node)
    
    has_node_key or has_source_node_key or has_originating_node_key
  end
  
  defp payload_has_node_field?({:error, _}), do: false
  defp payload_has_node_field?(_), do: false
end
