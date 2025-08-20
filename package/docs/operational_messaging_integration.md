# ExESDB Operational Messaging Integration

## Overview

This document describes the standardized operational messaging integration between ExESDB (core event store) and ExESDBGater (management layer). The integration ensures consistent node tracking, precise timestamps, and seamless message compatibility across both systems.

## Key Components

### 1. ExESDB.OperationalMessageHelpers

A utility module that provides:
- Consistent node field management (`node`, `source_node`, `originating_node`)
- Millisecond-precision UTC timestamps
- Message validation functions
- ExESDBGater compatibility layer
- Cluster context information

**Location:** `lib/ex_esdb/operational_message_helpers.ex`

### 2. Updated ExESDB.PubSubIntegration

Enhanced integration module that:
- Uses `OperationalMessageHelpers` for all payload creation
- Maintains backward compatibility
- Provides ExESDBGater message format compatibility
- Includes validation functions for message consistency

**Location:** `lib/ex_esdb/pubsub_integration.ex`

## Message Categories

### Operational Messages (Scope of This Integration)

These are system-level operational messages that flow through dedicated PubSub topics:

- **System Lifecycle** (`:ex_esdb_system`) - Startup, shutdown, configuration changes
- **Health Monitoring** (`:ex_esdb_health`) - Component and cluster health status
- **Performance Metrics** (`:ex_esdb_metrics`) - System performance data
- **Security Events** (`:ex_esdb_security`) - Authentication, authorization events
- **Audit Trail** (`:ex_esdb_audit`) - Compliance and tracking events
- **Critical Alerts** (`:ex_esdb_alerts`) - System alerts and notifications
- **Diagnostic Information** (`:ex_esdb_diagnostics`) - Debugging and troubleshooting
- **Process Lifecycle** (`:ex_esdb_lifecycle`) - Process start/stop events
- **Log Aggregation** (`:ex_esdb_logging`) - Centralized logging events

### Application Events (Excluded from This Integration)

- **Domain Events** (`:ex_esdb_events`) - Application-specific business events
- **Custom Application Topics** - User-defined event streams

## Node Field Standards

All operational messages now include consistent node tracking:

```elixir
# General operational events
%{node: Node.self()}

# ExESDB-specific events where source context matters
%{source_node: Node.self()}

# Cluster events needing distinction from affected nodes
%{originating_node: Node.self()}
```

## Timestamp Standards

All operational messages use millisecond-precision UTC timestamps:

```elixir
timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
```

This ensures:
- Consistent time formatting across systems
- Sufficient precision for ordering and debugging
- Compatibility with both ExESDB and ExESDBGater message formats

## Usage Examples

### Basic Operations

```elixir
# System lifecycle with standardized fields
ExESDB.PubSubIntegration.broadcast_system_lifecycle(
  :started, :ex_esdb, "1.0.0"
)

# Health update with node tracking
ExESDB.PubSubIntegration.broadcast_health_update(
  :store_worker, :healthy, %{store_id: :main_store}
)

# Metrics with precise timestamps
ExESDB.PubSubIntegration.broadcast_metrics(
  :persistence, %{operations: 100, duration_ms: 1500}
)

# Alerts with ExESDBGater compatibility
ExESDB.PubSubIntegration.broadcast_alert(
  :node_failure, :critical, "Node down", %{affected_node: :node1}
)
```

### Advanced Usage with Custom Node Information

```elixir
# Override default node for testing or proxying
ExESDB.PubSubIntegration.broadcast_health_update(
  :component, :degraded, %{reason: "high_load"}, 
  [node: :custom_node]
)

# Cluster events with originating node distinction
ExESDB.PubSubIntegration.broadcast_cluster_health(
  [:node1, :node2], [:node3], :node_failure,
  [originating_node: :management_node]
)
```

## Compatibility Validation

Test messaging compatibility between systems:

```elixir
# Validate integration works correctly
compatibility_report = ExESDB.PubSubIntegration.validate_messaging_compatibility()

# Example output:
%{
  operational_helpers: %{
    node_helper: true,
    timestamp_helper: %DateTime{...},
    cluster_context: %{node_name: :node@host, ...}
  },
  gater_integration: %{
    gater_available: true,
    tests: %{
      system_messages: :ok,
      health_messages: :ok,
      metrics_messages: :ok
    }
  },
  node_consistency: %{
    system_has_node: true,
    health_has_node: true
  },
  timestamp_precision: %{
    datetime_format: %DateTime{...},
    has_precision: true,
    millisecond_truncated: true
  }
}
```

## Configuration

Enable operational messaging in your ExESDB configuration:

```elixir
config :ex_esdb,
  # Enable PubSub integration
  pubsub_integration: true,
  
  # Broadcast intervals for automatic health/metrics updates
  health_broadcast_interval: 30_000,    # 30 seconds
  metrics_broadcast_interval: 60_000    # 60 seconds
```

## Integration Benefits

1. **Consistency** - All operational messages use standardized node and timestamp fields
2. **Compatibility** - Seamless interoperability between ExESDB and ExESDBGater
3. **Traceability** - Clear node attribution for distributed debugging
4. **Precision** - Millisecond-accurate timestamps for event ordering
5. **Validation** - Built-in message format validation
6. **Fallback** - Graceful degradation when ExESDBGater is not available
7. **Separation** - Clear distinction between operational and application events

## Migration Notes

### Existing Code

No breaking changes to existing ExESDB.PubSubIntegration API. All public functions maintain their signatures and behavior.

### Enhanced Features

- All operational messages now include consistent node fields
- Timestamps are now millisecond-precise
- Message validation is automatically applied
- ExESDBGater compatibility is handled transparently

### Monitoring

Use the compatibility validation function to ensure proper integration:

```elixir
# Add to your system health checks
case ExESDB.PubSubIntegration.validate_messaging_compatibility() do
  %{operational_helpers: %{node_helper: true}} -> :ok
  error_report -> Logger.warning("Messaging compatibility issues: #{inspect(error_report)}")
end
```

## Future Considerations

1. **Message Versioning** - Consider adding version fields for future message format evolution
2. **Compression** - Large message payloads might benefit from compression
3. **Encryption** - Sensitive operational data might need encryption in transit
4. **Batching** - Enhanced batch operations for high-throughput scenarios
5. **Schema Validation** - JSON Schema or similar for strict message format validation
