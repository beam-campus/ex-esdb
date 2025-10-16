# ExESDB PubSub Architecture and Event-Driven Design

## Overview

ExESDB integrates with ExESDBGater's comprehensive PubSub (Publish-Subscribe) messaging system to provide real-time monitoring, observability, and event-driven architecture across the entire cluster. This integration enables dashboards, monitoring tools, and external systems to receive live updates about cluster state changes, health status, performance metrics, and diagnostic information.

## Architecture Components

### ExESDBGater Message System

ExESDB leverages ExESDBGater's 9 dedicated PubSub instances for different types of system events:

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

### Integration Helper Module

The `ExESDB.PubSubIntegration` module provides a centralized, idiomatic Elixir interface for broadcasting events:

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

## Enhanced EmitterWorker System

### Color-Coded Observability

The EmitterWorker system now provides comprehensive, color-coded logging for different message types:

#### Message Type Color Coding
- **🟢 Success Messages (White on Green/Blue)**: Service activation, health subscriptions, successful operations
- **🔴 Failure Messages (White on Red)**: Termination events, errors, unhealthy states  
- **🟡 Action Messages (White on Amber)**: Broadcasting, forwarding, dynamic worker creation, metrics
- **🔵 Health Messages (White on Cyan)**: Health event processing, status changes

### Comprehensive Event Logging

#### Health Event Monitoring
```elixir
# Health event subscription
🩺 SUBSCRIBED to health events for store: my_store

# Individual health events
📡 HEALTH EVENT: subscription_name -> event_type (metadata)

# Health summaries
📈 HEALTH SUMMARY: Store my_store - 5/7 healthy subscriptions

# Health impact on emission
🏥 HEALTH IMPACT: subscription_name is HEALTHY (registration_success)
```

#### Metrics Event Monitoring
```elixir
# Metrics event subscription
📈 SUBSCRIBED to metrics events for store: my_store

# Individual metrics events
📈 METRICS EVENT: my_store -> events_per_second=1250 @2025-07-27T11:30:00Z

# Metrics summaries
📉 METRICS SUMMARY: Store my_store - 1250 eps, 50000 total, 12 active subs
```

#### Lifecycle Events
```elixir
# Worker activation with complete information
┌──────────────────────────────────────────────────────────────────────┐
★ EMITTER WORKER ACTIVATION ★
├──────────────────────────────────────────────────────────────────────┤
Topic:      "my_store:stream_name"
Store:      my_store
Scheduler:  2
PID:        #PID<0.511.0>
Subscriber: #PID<0.312.0>
└──────────────────────────────────────────────────────────────────────┘

# Worker termination with subscriber information
╔══════════════════════════════════════════════════════════════════════╗
💀 EMITTER WORKER TERMINATION 💀
╠══════════════════════════════════════════════════════════════════════╣
Reason:     :shutdown
Store:      my_store
Selector:   stream_name
Subscriber: #PID<0.312.0>
PID:        #PID<0.511.0>
╚══════════════════════════════════════════════════════════════════════╝
```

## Event-Driven Architecture Benefits

### 1. Separation of Concerns
- **Dedicated channels** prevent cross-contamination of different message types
- **Specialized handling** for events, system operations, and health monitoring
- **Clean boundaries** between business logic and operational concerns

### 2. Enhanced Observability
- **Real-time visibility** into system health and performance
- **Color-coded logging** for immediate visual identification of issues
- **Comprehensive metrics** collection and reporting
- **Detailed lifecycle tracking** for all system components

### 3. Improved Reliability
- **Health-aware emission**: EmitterWorkers can pause/resume based on subscription health
- **Circuit breaker integration**: Automatic handling of degraded services
- **Graceful degradation**: System continues operating during partial failures

### 4. Better Performance
- **Asynchronous messaging**: Non-blocking communication between components
- **Efficient broadcasting**: Dedicated channels reduce message routing overhead
- **Batch processing**: Health and metrics events can be batched for efficiency

## Implementation Details

### Subscription Health Tracking

The `ExESDB.SubscriptionHealthTracker` has been enhanced to use the dedicated `:ex_esdb_health` PubSub instance:

```elixir
# Subscribe to health events
Phoenix.PubSub.subscribe(:ex_esdb_health, "store_health:#{store_id}")

# Broadcast health events  
Phoenix.PubSub.broadcast(:ex_esdb_health, "store_health:#{store_id}", 
  {:subscription_health, health_event})

# Broadcast health summaries
Phoenix.PubSub.broadcast(:ex_esdb_health, "health_summary:#{store_id}", 
  {:health_summary, summary_data})
```

### EmitterWorker Health Integration

EmitterWorkers now subscribe to both health and metrics events:

```elixir
def init({store, sub_topic, subscriber}) do
  # Subscribe to health events
  Phoenix.PubSub.subscribe(:ex_esdb_health, "store_health:#{store}")
  Phoenix.PubSub.subscribe(:ex_esdb_health, "health_summary:#{store}")
  
  # Subscribe to metrics events
  Phoenix.PubSub.subscribe(:ex_esdb_system, "store_metrics:#{store}")
  Phoenix.PubSub.subscribe(:ex_esdb_system, "metrics_summary:#{store}")
  
  # ... rest of initialization
end
```

### Health-Aware Emission Control

EmitterWorkers can dynamically adjust their behavior based on health status:

```elixir
defp update_emission_state(healthy) do
  Process.put(:emitter_active, healthy)
  
  if healthy do
    Logger.debug("Emission RESUMED due to healthy status")
  else
    Logger.warning("Emission PAUSED due to unhealthy status")
  end
end
```

## Configuration

### PubSub Instance Configuration

The PubSub instances are automatically configured as part of the ExESDB system:

```elixir
# In your application's supervision tree
children = [
  {Phoenix.PubSub, name: :ex_esdb_events},
  {Phoenix.PubSub, name: :ex_esdb_system}, 
  {Phoenix.PubSub, name: :ex_esdb_health},
  # ... other children
]
```

### Health Monitoring Configuration

Health tracking can be configured per store:

```elixir
config :ex_esdb, :health_monitoring,
  enabled: true,
  check_interval: 5_000,
  unhealthy_threshold: 3,
  circuit_breaker_enabled: true
```

## Migration Path to Full EDA

This PubSub architecture serves as the foundation for migrating ExESDB to a fully Event-Driven Architecture:

### Phase 1: Internal Events (Current)
- ✅ Dedicated PubSub instances
- ✅ Health event distribution
- ✅ Metrics event distribution
- ✅ Enhanced observability

### Phase 2: Domain Events (Next)
- [ ] Business domain event modeling
- [ ] Event sourcing patterns
- [ ] Saga orchestration
- [ ] Event replay capabilities

### Phase 3: External Integration (Future)
- [ ] External system notifications
- [ ] Webhook delivery
- [ ] Message queue integration
- [ ] Event streaming to external systems

## Best Practices

### 1. Topic Naming Conventions
- Use consistent prefixes: `"store_health:"`, `"store_metrics:"`, `"stream:"`
- Include store ID for multi-tenant deployments
- Use descriptive, hierarchical names

### 2. Message Structure
- Include timestamp and correlation IDs
- Use structured data (maps) for complex events
- Maintain backward compatibility in message formats

### 3. Error Handling
- Implement proper error handling in all subscribers
- Use circuit breakers for external integrations
- Log errors with appropriate context

### 4. Performance Considerations
- Batch messages when possible
- Use async processing for non-critical events
- Monitor PubSub performance and tune accordingly

## Monitoring and Debugging

### Health Dashboard
Monitor system health through dedicated health events:
- Subscription health status
- Circuit breaker states
- Service availability metrics

### Performance Metrics
Track system performance through metrics events:
- Events per second
- Processing latency
- Active subscription counts
- Memory and CPU usage

### Debugging Tools
Use the enhanced logging for debugging:
- Color-coded message identification
- Detailed lifecycle tracking
- Health event correlation
- Performance bottleneck identification

## Conclusion

The enhanced PubSub architecture transforms ExESDB into a highly observable, resilient, and scalable event store system. By providing dedicated communication channels for different concerns and comprehensive observability features, this architecture serves as a solid foundation for evolving toward a fully Event-Driven Architecture while maintaining operational excellence and system reliability.

The color-coded logging, health-aware emission control, and comprehensive metrics collection provide unprecedented visibility into system operations, making it easier to develop, debug, and operate ExESDB-based applications in production environments.
