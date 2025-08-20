# ExESDB Monitoring and Observability

This guide covers the comprehensive monitoring and observability features built into ExESDB, including health tracking, performance metrics, and diagnostic capabilities.

## Overview

ExESDB provides extensive monitoring capabilities through multiple layers:
- **Health Monitoring**: System and component health tracking
- **Performance Metrics**: Real-time performance measurement
- **Diagnostic Tools**: Debug traces and system state analysis
- **Color-Coded Logging**: Visual identification of different event types
- **Alert System**: Proactive notification of issues

## Health Monitoring System

### Component Health Tracking

ExESDB tracks health at multiple levels:

```elixir
# Individual component health
%HealthMessages.ComponentHealth{
  component: :store_worker,
  node: Node.self(),
  status: :healthy,  # :healthy | :degraded | :unhealthy
  details: %{
    store_id: "main_store",
    memory_usage: 45.2,
    response_time_ms: 12
  },
  last_check: DateTime.utc_now(),
  timestamp: DateTime.utc_now()
}
```

### Cluster Health Overview

```elixir
# Cluster-wide health status
%HealthMessages.ClusterHealth{
  status: :healthy,          # Overall cluster status
  healthy_nodes: 3,          # Count of healthy nodes
  total_nodes: 4,            # Total nodes in cluster
  degraded_nodes: [:node2],  # Nodes with degraded performance
  unhealthy_nodes: [:node4], # Failed or unresponsive nodes
  quorum_status: :available, # :available | :lost
  timestamp: DateTime.utc_now()
}
```

### Health Check Results

```elixir
# Individual health check outcomes
%HealthMessages.HealthCheck{
  check_name: :persistence_check,
  node: Node.self(),
  result: :pass,              # :pass | :fail | :timeout
  duration_ms: 150,           # Check execution time
  details: %{
    stores_checked: 5,
    avg_response_time: 45
  },
  error: nil,                 # Error message if failed
  timestamp: DateTime.utc_now()
}
```

## Performance Metrics

### Throughput Metrics

Track operation rates and throughput:

```elixir
%MetricsMessages.ThroughputMetric{
  operation: :event_emission,
  count: 1250,               # Operations in time window
  duration_ms: 1000,         # Time window duration
  rate_per_sec: 1250.0,      # Calculated rate
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

### Latency Metrics

Monitor response times and latency:

```elixir
%MetricsMessages.LatencyMetric{
  operation: :persistence_write,
  latency_ms: 45.2,          # Measured latency
  percentile: :p95,          # :p50 | :p95 | :p99 | :max | :min | :avg
  sample_count: 1000,        # Number of samples
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

### Resource Usage Metrics

Track system resource consumption:

```elixir
%MetricsMessages.ResourceUsage{
  resource_type: :memory,     # :cpu | :memory | :disk | :network
  usage_percent: 67.8,       # Current usage percentage
  total_available: 8_589_934_592,  # Total resource available (bytes)
  current_used: 5_838_471_372,    # Currently used (bytes)
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

### Performance Alerts

Automatic alerts for threshold violations:

```elixir
%MetricsMessages.MetricAlert{
  metric_name: :memory_usage,
  current_value: 89.5,       # Current metric value
  threshold_value: 85.0,     # Configured threshold
  threshold_type: :max,      # :min | :max
  severity: :warning,        # :warning | :critical
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

## Color-Coded Observability

### EmitterWorker Logging

The EmitterWorker system provides color-coded logging for visual identification:

#### Success Messages (🟢 Green/Blue)
```elixir
# Service activation
★ EMITTER WORKER ACTIVATION ★
Topic:      "my_store:stream_name"
Store:      my_store
Scheduler:  2
PID:        #PID<0.511.0>
Subscriber: #PID<0.312.0>

# Health subscriptions
🩺 SUBSCRIBED to health events for store: my_store
```

#### Failure Messages (🔴 Red)
```elixir
# Worker termination
💀 EMITTER WORKER TERMINATION 💀
Reason:     :shutdown
Store:      my_store
Selector:   stream_name
Subscriber: #PID<0.312.0>
PID:        #PID<0.511.0>

# Error conditions
❌ STORE FAILURE: my_store - Connection timeout
```

#### Action Messages (🟡 Amber)
```elixir
# Broadcasting activities
📡 BROADCASTING: Event emitted to store: my_store
📤 FORWARDING: Message forwarded to subscriber

# Metrics collection
📈 METRICS COLLECTED: my_store - 1250 ops/sec
```

#### Health Messages (🔵 Cyan)
```elixir
# Health events
📡 HEALTH EVENT: subscription_name -> healthy (registration_success)
📈 HEALTH SUMMARY: Store my_store - 5/7 healthy subscriptions
🏥 HEALTH IMPACT: subscription_name is HEALTHY
```

## Diagnostic Tools

### Debug Traces

Capture detailed debug information:

```elixir
%DiagnosticsMessages.DebugTrace{
  component: :store_worker,
  trace_type: :performance_analysis,
  data: %{
    function_calls: 1250,
    memory_allocations: 45,
    gc_collections: 3,
    message_queue_length: 12
  },
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

### Performance Analysis

Deep dive into performance characteristics:

```elixir
%DiagnosticsMessages.PerformanceAnalysis{
  component: :persistence_worker,
  analysis_type: :bottleneck_detection,
  duration_ms: 5000,           # Analysis duration
  results: %{
    bottlenecks: [:disk_io, :network_latency],
    recommendations: ["Increase disk IOPS", "Optimize network topology"],
    performance_score: 78.5
  },
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

### System State Snapshots

Capture current system state:

```elixir
%DiagnosticsMessages.SystemState{
  snapshot_type: :memory_usage,
  state_data: %{
    total_memory: 8_589_934_592,
    used_memory: 5_838_471_372,
    process_count: 1247,
    largest_processes: [
      %{pid: "#PID<0.123.0>", memory: 125_829_120, name: "store_worker_main"},
      %{pid: "#PID<0.456.0>", memory: 89_478_485, name: "emitter_pool"}
    ]
  },
  node: Node.self(),
  timestamp: DateTime.utc_now()
}
```

## Alert System

### System Alerts

Critical system-wide notifications:

```elixir
%AlertMessages.SystemAlert{
  alert_type: :node_failure,
  severity: :critical,         # :info | :warning | :critical
  message: "Node node2 has become unresponsive",
  context: %{
    failed_node: :node2,
    cluster_size: 3,
    quorum_status: :available,
    estimated_recovery_time: "5-10 minutes"
  },
  timestamp: DateTime.utc_now()
}
```

### Alert Acknowledgment

Track alert handling:

```elixir
%AlertMessages.AlertAck{
  alert_id: "alert_12345",
  acknowledged_by: "admin@company.com",
  ack_message: "Investigating node failure",
  auto_ack: false,             # Manual vs automatic acknowledgment
  timestamp: DateTime.utc_now()
}
```

### Alert Escalation

Handle unacknowledged alerts:

```elixir
%AlertMessages.AlertEscalation{
  original_alert_id: "alert_12345",
  escalation_level: 2,         # Escalation tier
  escalated_to: ["oncall@company.com", "manager@company.com"],
  escalation_reason: "No acknowledgment after 15 minutes",
  timestamp: DateTime.utc_now()
}
```

## Monitoring Integration Examples

### Prometheus/Grafana Integration

```elixir
defmodule MyApp.PrometheusExporter do
  use GenServer
  
  def init(_) do
    # Subscribe to metrics
    Phoenix.PubSub.subscribe(:ex_esdb_metrics, "performance")
    Phoenix.PubSub.subscribe(:ex_esdb_health, "cluster_health")
    {:ok, %{}}
  end
  
  def handle_info({:performance_metric, metric}, state) do
    :prometheus_gauge.set(
      :exesdb_performance, 
      [component: metric.component, node: metric.node], 
      metric.value
    )
    {:noreply, state}
  end
  
  def handle_info({:cluster_health_updated, health}, state) do
    :prometheus_gauge.set(:exesdb_healthy_nodes, [], health.healthy_nodes)
    :prometheus_gauge.set(:exesdb_total_nodes, [], health.total_nodes)
    {:noreply, state}
  end
end
```

### PagerDuty Integration

```elixir
defmodule MyApp.PagerDutyNotifier do
  use GenServer
  
  def init(_) do
    Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
    Phoenix.PubSub.subscribe(:ex_esdb_alerts, "persistence_failure")
    {:ok, %{}}
  end
  
  def handle_info({:system_alert, %{severity: :critical} = alert}, state) do
    PagerDuty.trigger_incident(%{
      routing_key: "exesdb_routing_key",
      event_action: "trigger",
      payload: %{
        summary: alert.message,
        severity: "critical",
        source: "ExESDB Cluster",
        component: alert.context.component || "unknown",
        custom_details: alert.context
      }
    })
    {:noreply, state}
  end
end
```

### Slack Notifications

```elixir
defmodule MyApp.SlackNotifier do
  use GenServer
  
  def handle_info({:system_alert, alert}, state) do
    emoji = case alert.severity do
      :critical -> "🚨"
      :warning -> "⚠️"
      :info -> "ℹ️"
    end
    
    message = """
    #{emoji} ExESDB Alert
    
    **Severity:** #{alert.severity}
    **Type:** #{alert.alert_type}
    **Message:** #{alert.message}
    **Node:** #{alert.context[:node] || "Unknown"}
    **Time:** #{DateTime.to_string(alert.timestamp)}
    """
    
    Slack.send_message("#exesdb-alerts", message)
    {:noreply, state}
  end
end
```

## Monitoring Dashboard Example

```elixir
defmodule MyApp.MonitoringDashboard do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all monitoring channels
      Phoenix.PubSub.subscribe(:ex_esdb_health, "cluster_health")
      Phoenix.PubSub.subscribe(:ex_esdb_metrics, "performance")
      Phoenix.PubSub.subscribe(:ex_esdb_alerts, "node_failure")
      Phoenix.PubSub.subscribe(:ex_esdb_diagnostics, "performance_analysis")
    end
    
    {:ok, assign(socket, 
      cluster_health: %{},
      performance_metrics: [],
      active_alerts: [],
      diagnostic_data: %{}
    )}
  end
  
  def handle_info({:cluster_health_updated, health}, socket) do
    {:noreply, assign(socket, :cluster_health, health)}
  end
  
  def handle_info({:performance_metric, metric}, socket) do
    metrics = [metric | socket.assigns.performance_metrics]
    |> Enum.take(100)  # Keep last 100 metrics
    
    {:noreply, assign(socket, :performance_metrics, metrics)}
  end
  
  def handle_info({:system_alert, alert}, socket) do
    alerts = [alert | socket.assigns.active_alerts]
    |> Enum.filter(&(&1.severity in [:warning, :critical]))
    |> Enum.take(50)  # Keep last 50 alerts
    
    {:noreply, assign(socket, :active_alerts, alerts)}
  end
end
```

## Best Practices

### 1. Monitoring Strategy
- Monitor at multiple levels: system, cluster, component, and process
- Set appropriate thresholds for alerts to avoid noise
- Use color-coded logging for quick visual identification
- Implement automated health checks and recovery procedures

### 2. Performance Monitoring
- Track key metrics: throughput, latency, resource usage
- Monitor trends over time, not just current values
- Set up alerts for performance degradation
- Use percentile-based metrics for better insights

### 3. Alert Management
- Implement alert escalation procedures
- Use different alert channels for different severities
- Provide sufficient context in alert messages
- Track alert acknowledgment and resolution times

### 4. Diagnostic Data
- Collect diagnostic data proactively
- Store system state snapshots for historical analysis
- Use structured logging for better searchability
- Implement automatic diagnostic collection during incidents

This comprehensive monitoring and observability system ensures that you have complete visibility into your ExESDB cluster's health, performance, and behavior, enabling proactive maintenance and rapid incident response.
