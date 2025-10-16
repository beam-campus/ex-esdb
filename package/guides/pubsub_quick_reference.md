# ExESDB PubSub Quick Reference

This is a quick reference guide for the ExESDB PubSub integration with ExESDBGater.

## Quick Setup

### 1. Enable Integration

```elixir
# config/config.exs
config :ex_esdb,
  pubsub_integration: true,
  health_broadcast_interval: 30_000,
  metrics_broadcast_interval: 60_000

# Optional: Configure message security
config :ex_esdb_gater,
  secret_key_base: System.get_env("SECRET_KEY_BASE")
```

### 2. Runtime Control

```elixir
# Enable/disable at runtime
ExESDB.PubSubIntegration.enable!()
ExESDB.PubSubIntegration.disable!()

# Check status
ExESDB.PubSubIntegration.enabled?()
```

## Broadcasting Events

### System Events

```elixir
# System lifecycle
ExESDB.PubSubIntegration.broadcast_system_lifecycle(:started, :ex_esdb, "0.8.0")

# Configuration changes
ExESDB.PubSubIntegration.broadcast_system_config(:store, %{enabled: true})
```

### Health Events

```elixir
# Component health
ExESDB.PubSubIntegration.broadcast_health_update(:store_worker, :healthy, %{store_id: "main"})

# Cluster health
ExESDB.PubSubIntegration.broadcast_cluster_health(nodes, failed_nodes, :node_down)
```

### Performance Metrics

```elixir
# Generic metrics
ExESDB.PubSubIntegration.broadcast_metrics(:persistence, %{
  operations_count: 1000,
  duration_ms: 250,
  success_count: 995,
  error_count: 5
})
```

### Alerts

```elixir
# System alerts
ExESDB.PubSubIntegration.broadcast_alert(:node_failure, :critical, "Node down", %{node: :node1})
```

## Subscribing to Events

### Basic Subscription

```elixir
# Subscribe to specific topics
Phoenix.PubSub.subscribe(:ex_esdb_system, "lifecycle")
Phoenix.PubSub.subscribe(:ex_esdb_health, "cluster_health")
Phoenix.PubSub.subscribe(:ex_esdb_metrics, "persistence")
Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
```

### LiveView Integration

```elixir
defmodule MyApp.DashboardLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(:ex_esdb_health, "cluster_health")
      Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
    end
    {:ok, assign(socket, :status, %{})}
  end
  
  def handle_info({:node_health_updated, payload}, socket) do
    {:noreply, assign(socket, :status, payload)}
  end
  
  def handle_info({:system_alert, alert}, socket) do
    {:noreply, put_flash(socket, :error, alert.message)}
  end
end
```

### GenServer Integration

```elixir
defmodule MyApp.MonitoringWorker do
  use GenServer
  
  def init(_) do
    Phoenix.PubSub.subscribe(:ex_esdb_metrics, "performance")
    Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
    {:ok, %{}}
  end
  
  def handle_info({:performance_metric, metric}, state) do
    # Process metric
    {:noreply, state}
  end
  
  def handle_info({:system_alert, alert}, state) do
    # Handle alert
    {:noreply, state}
  end
end
```

## Message Validation

### Secure Messages

```elixir
def handle_info(raw_message, state) do
  case ExESDBGater.Messages.HealthMessages.validate_secure_message(raw_message) do
    {:ok, {:node_health_updated, payload}} ->
      handle_health_update(payload, state)
    
    {:error, :invalid_signature} ->
      Logger.warning("Invalid message signature")
      {:noreply, state}
    
    {:error, :no_secret_configured} ->
      Logger.warning("No secret configured for validation")
      {:noreply, state}
  end
end
```

## PubSub Instances Reference

| Instance | Topics | Message Types |
|----------|--------|---------------|
| `:ex_esdb_system` | "lifecycle", "config" | SystemLifecycle, SystemConfig |
| `:ex_esdb_health` | "cluster_health", "component_health" | NodeHealth, ClusterHealth |
| `:ex_esdb_metrics` | "performance", "persistence" | PerformanceMetric, ThroughputMetric |
| `:ex_esdb_alerts` | "node_failure", "persistence_failure" | SystemAlert |
| `:ex_esdb_audit` | "data_change", "admin_action" | DataChange, AdminAction |
| `:ex_esdb_diagnostics` | "debug_trace", "performance_analysis" | DebugTrace |
| `:ex_esdb_lifecycle` | "process_lifecycle" | ProcessLifecycle |
| `:ex_esdb_security` | "auth_event", "access_violation" | AuthEvent |
| `:ex_esdb_logging` | "log_entry", "log_summary" | LogEntry |

## Common Message Patterns

### Health Messages

```elixir
# Node health
{:node_health_updated, %HealthMessages.NodeHealth{
  node: :node1,
  status: :healthy,
  checks: %{persistence: :pass, network: :pass},
  memory_usage: 45.2,
  timestamp: ~U[2024-08-15 12:00:00Z]
}}

# Cluster health
{:cluster_health_updated, %HealthMessages.ClusterHealth{
  status: :healthy,
  healthy_nodes: 3,
  total_nodes: 4,
  degraded_nodes: [],
  unhealthy_nodes: [:node4],
  timestamp: ~U[2024-08-15 12:00:00Z]
}}
```

### Metric Messages

```elixir
# Performance metric
{:performance_metric, %MetricsMessages.PerformanceMetric{
  metric_name: :persistence_operation,
  value: 1000,
  unit: "operations",
  component: :persistence,
  node: :node1,
  timestamp: ~U[2024-08-15 12:00:00Z]
}}

# Throughput metric
{:throughput_metric, %MetricsMessages.ThroughputMetric{
  operation: :event_emission,
  count: 1250,
  duration_ms: 1000,
  rate_per_sec: 1250.0,
  node: :node1,
  timestamp: ~U[2024-08-15 12:00:00Z]
}}
```

### Alert Messages

```elixir
# System alert
{:system_alert, %AlertMessages.SystemAlert{
  alert_type: :node_failure,
  severity: :critical,
  message: "Node node2 has become unresponsive",
  context: %{failed_node: :node2, cluster_size: 3},
  timestamp: ~U[2024-08-15 12:00:00Z]
}}
```

## Troubleshooting

### Common Issues

1. **Messages not received**
   - Check topic names match exactly
   - Verify PubSub instance names
   - Ensure processes are still alive

2. **Invalid signature errors**
   - Check SECRET_KEY_BASE configuration
   - Verify same secret across all nodes
   - Check clock synchronization

3. **High memory usage**
   - Reduce broadcast intervals
   - Implement selective subscription
   - Monitor message queue lengths

### Debug Commands

```elixir
# Check integration status
ExESDB.PubSubIntegration.enabled?()
ExESDB.PubSubIntegration.health_broadcast_interval()
ExESDB.PubSubIntegration.metrics_broadcast_interval()

# List subscribers
Phoenix.PubSub.subscribers(:ex_esdb_health, "cluster_health")

# Check process info
Process.info(self(), [:message_queue_len, :memory])
```

## Performance Tips

- Use topic-based filtering to reduce processing
- Implement message batching for high frequency events
- Set appropriate broadcast intervals
- Monitor subscriber performance
- Use structured logging for debugging
