# ExESDB PubSub Integration with ExESDBGater

This guide covers the comprehensive PubSub integration between ExESDB and ExESDBGater, enabling real-time monitoring, observability, and event-driven architecture.

## Overview

ExESDB integrates with ExESDBGater's structured messaging system to provide real-time visibility into system operations, health status, performance metrics, and diagnostic information. This integration enables dashboards, monitoring tools, and external systems to receive live updates about cluster state changes.

## ExESDBGater Message System

ExESDB leverages ExESDBGater's 9 dedicated PubSub instances:

| PubSub Instance | Purpose | Message Types |
|----------------|---------|---------------|
| `:ex_esdb_system` | System lifecycle and configuration | SystemLifecycle, SystemConfig |
| `:ex_esdb_health` | Health monitoring and status | NodeHealth, ClusterHealth, ComponentHealth |
| `:ex_esdb_metrics` | Performance metrics | PerformanceMetric, ThroughputMetric, LatencyMetric |
| `:ex_esdb_lifecycle` | Process and node lifecycle | ProcessLifecycle, ClusterMembership |
| `:ex_esdb_alerts` | Critical alerts and notifications | SystemAlert, AlertAck, AlertEscalation |
| `:ex_esdb_audit` | Audit trail and compliance | DataChange, AdminAction, AccessLog |
| `:ex_esdb_diagnostics` | Debug and troubleshooting | DebugTrace, PerformanceAnalysis |
| `:ex_esdb_security` | Security events | AuthEvent, AccessViolation, SecurityAlert |
| `:ex_esdb_logging` | Log aggregation | LogEntry, LogSummary, LogRotation |

## Integration Helper Module

The `ExESDB.PubSubIntegration` module provides a centralized, idiomatic Elixir interface:

```elixir
# System lifecycle events
ExESDB.PubSubIntegration.broadcast_system_lifecycle(:started, :ex_esdb, "0.8.0")

# Health updates
ExESDB.PubSubIntegration.broadcast_health_update(:store_worker, :healthy, %{store_id: "main"})

# Performance metrics
ExESDB.PubSubIntegration.broadcast_metrics(:persistence, %{
  operations_count: 1000,
  duration_ms: 250,
  success_count: 995,
  error_count: 5
})

# Critical alerts
ExESDB.PubSubIntegration.broadcast_alert(:node_failure, :critical, "Node down", %{node: :node1})
```

## Core Integration Points

### 1. System Lifecycle (`ExESDB.System`)

Broadcasts system startup, shutdown, and configuration changes:

```elixir
# Startup broadcast
ExESDB.PubSubIntegration.broadcast_system_lifecycle(
  :started, 
  :ex_esdb, 
  Application.spec(:ex_esdb, :vsn)
)

# Configuration change broadcast
ExESDB.PubSubIntegration.broadcast_system_config(
  :store_config,
  %{store_id: store_id, enabled: true},
  topic: "config"
)
```

### 2. Store Operations (`ExESDB.StoreWorker`)

Broadcasts store lifecycle and health events:

```elixir
# Store health update
ExESDB.PubSubIntegration.broadcast_health_update(
  :store_worker,
  :healthy,
  %{store_id: store_id, status: :running}
)

# Store failure alert
ExESDB.PubSubIntegration.broadcast_alert(
  :store_failure,
  :critical,
  "Store worker failed",
  %{store_id: store_id, reason: reason}
)
```

### 3. Health Monitoring (`ExESDB.Monitoring.HealthChecker`)

Broadcasts system health and resource utilization:

```elixir
ExESDB.PubSubIntegration.broadcast_health_update(
  :health_checker,
  health_status,
  %{
    cpu_usage: 45.2,
    memory_usage: 67.8,
    disk_usage: 23.1,
    check_duration_ms: 150
  }
)
```

### 4. Cluster Monitoring (`ExESDB.NodeMonitor`)

Broadcasts cluster events and node status:

```elixir
# Node failure alert
ExESDB.PubSubIntegration.broadcast_alert(
  :node_failure,
  :critical,
  "Node disconnected",
  %{node: down_node, cluster_size: length(connected_nodes)}
)

# Cluster health update
ExESDB.PubSubIntegration.broadcast_cluster_health(
  connected_nodes,
  [down_node],
  :node_down
)
```

### 5. Persistence Monitoring (`ExESDB.PersistenceWorker`)

Broadcasts persistence operation metrics and alerts:

```elixir
ExESDB.PubSubIntegration.broadcast_metrics(
  :persistence,
  %{
    stores_count: stores_count,
    duration_ms: duration_ms,
    success_count: success_count,
    error_count: error_count
  }
)
```

## Configuration

### Enable/Disable Integration

```elixir
# config/config.exs
config :ex_esdb,
  # Enable pubsub integration for dashboard and monitoring
  pubsub_integration: true,
  # Interval for health status broadcasts (30 seconds)
  health_broadcast_interval: 30_000,
  # Interval for metrics broadcasts (60 seconds)
  metrics_broadcast_interval: 60_000
```

### Runtime Control

```elixir
# Enable at runtime
ExESDB.PubSubIntegration.enable!()

# Disable at runtime
ExESDB.PubSubIntegration.disable!()

# Check status
ExESDB.PubSubIntegration.enabled?()
```

### Message Security

All messages are cryptographically signed using HMAC-SHA256:

```elixir
# config/config.exs
config :ex_esdb_gater,
  secret_key_base: System.get_env("SECRET_KEY_BASE")
```

## Subscription Examples

### Dashboard Integration

```elixir
defmodule MyApp.DashboardLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(:ex_esdb_system, "lifecycle")
      Phoenix.PubSub.subscribe(:ex_esdb_health, "cluster_health")
      Phoenix.PubSub.subscribe(:ex_esdb_metrics, "persistence")
      Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
    end
    
    {:ok, assign(socket, :cluster_status, %{})}
  end
  
  def handle_info({:node_health_updated, payload}, socket) do
    {:noreply, update_health_display(socket, payload)}
  end
end
```

### External Monitoring

```elixir
defmodule MyApp.MetricsCollector do
  use GenServer
  
  def init(_opts) do
    Phoenix.PubSub.subscribe(:ex_esdb_metrics, "persistence")
    Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
    {:ok, %{}}
  end
  
  def handle_info({:performance_metric, %{value: value, component: component}}, state) do
    MyApp.Prometheus.set_gauge("exesdb_#{component}_performance", value)
    {:noreply, state}
  end
end
```

## Message Validation

Always validate received messages for security:

```elixir
def handle_info(raw_message, state) do
  case ExESDBGater.Messages.HealthMessages.validate_secure_message(raw_message) do
    {:ok, {:node_health_updated, payload}} ->
      handle_health_update(payload, state)
    
    {:error, :invalid_signature} ->
      Logger.warning("Received message with invalid signature")
      {:noreply, state}
  end
end
```

## Performance Considerations

- **Health updates**: Every 30 seconds (configurable)
- **Metrics**: Every 60 seconds (configurable)
- **Alerts**: Immediate
- **Resource usage**: ~1-2% CPU per 1000 messages/second
- **Network bandwidth**: ~1KB per message average

## Troubleshooting

### Common Issues

1. **Messages not received**: Check PubSub subscription topic names
2. **Invalid signature errors**: Verify SECRET_KEY_BASE consistency
3. **High memory usage**: Reduce broadcast intervals or implement selective subscription

### Debug Mode

```elixir
# Check integration status
ExESDB.PubSubIntegration.enabled?()
ExESDB.PubSubIntegration.health_broadcast_interval()
ExESDB.PubSubIntegration.metrics_broadcast_interval()
```
