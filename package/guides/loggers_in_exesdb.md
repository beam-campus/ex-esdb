# Logger Filtering in ExESDB Event Store

ExESDB is built on top of several distributed systems components that can generate significant amounts of log noise during normal operation. To provide a better developer experience and cleaner production logs, ExESDB implements a comprehensive logger filtering system.

## Overview

ExESDB uses a two-tier approach to logger filtering:

1. **BCUtils.LoggerFilters** - Provides general-purpose filtering for common BEAM distributed systems
2. **ExESDB.LoggerFilters** - Provides specialized filtering for ExESDB's core infrastructure components

This layered approach ensures comprehensive noise reduction while maintaining full visibility into errors and warnings.

## BCUtils Logger Filtering

BCUtils provides foundational logger filtering for commonly used distributed systems libraries:

### Swarm Process Registry
- Filters routine process registration/unregistration messages
- Reduces noise from node up/down events
- Maintains visibility into registry errors and conflicts

### LibCluster Auto-Clustering
- Filters cluster formation and gossip protocol messages
- Reduces connection/disconnection event noise
- Preserves cluster formation failures and split-brain warnings

## ExESDB Logger Filtering

ExESDB extends the filtering capabilities with specialized filters for its core infrastructure:

### Ra Consensus Library Filtering

The Ra consensus library is fundamental to ExESDB's distributed operation but generates substantial log noise during normal consensus operations.

**Filtered Messages:**
- Heartbeat messages between Ra nodes
- `append_entries` consensus protocol messages
- `pre_vote` and `request_vote` election messages
- Routine state transitions (follower ↔ candidate ↔ leader)
- Internal Ra module operations at info/debug levels

**Preserved Messages:**
- All error and warning level messages
- Election failures and split-brain scenarios
- Consensus failures and recovery operations

### Khepri Database Filtering

Khepri serves as ExESDB's distributed database backend and can be verbose about internal operations.

**Filtered Messages:**
- Cluster state synchronization messages
- Store operation confirmations
- Routine cluster member coordination
- Internal Khepri module operations at info/debug levels

**Preserved Messages:**
- Database errors and transaction failures
- Cluster coordination problems
- Data consistency warnings

### Enhanced Swarm & LibCluster Filtering

ExESDB provides additional filtering beyond BCUtils for ExESDB-specific use cases:

**Enhanced Swarm Filtering:**
- ExESDB-specific process registry patterns
- Stream coordinator registration/unregistration
- Event emitter lifecycle messages

**Enhanced LibCluster Filtering:**
- ExESDB cluster topology changes
- Node role transitions (leader/follower)
- Gateway API cluster coordination

## Configuration

### Development Environment

In development, you may want to see more detailed logs. Configure your logger in `config/dev.exs`:

```elixir
# Minimal filtering - see more activity
config :logger, :console,
  level: :debug,
  format: "[$level] $message\n"

# Apply only critical noise reduction
config :logger, 
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]
```

### Production Environment

For production, apply comprehensive filtering in `config/prod.exs`:

```elixir
# Apply all ExESDB logger filters
config :logger,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Add custom filters
config :logger, :console,
  level: :info,
  format: "[$level] $message\n",
  metadata_filter: [
    {ExESDB.LoggerFilters, :filter_ra},
    {ExESDB.LoggerFilters, :filter_khepri},
    {ExESDB.LoggerFilters, :filter_swarm},
    {ExESDB.LoggerFilters, :filter_libcluster}
  ]
```

## Custom Filtering

You can extend the filtering system for your specific needs:

```elixir
defmodule MyApp.CustomLoggerFilters do
  def filter_my_component(log_event) do
    case log_event do
      {level, _gl, {Logger, msg, _ts, metadata}} ->
        if should_filter_my_component?(level, msg, metadata) do
          :stop
        else
          :ignore
        end
      _ ->
        :ignore
    end
  end

  defp should_filter_my_component?(level, msg, metadata) do
    # Your custom filtering logic
    level in [:info, :debug] and routine_operation?(msg)
  end
end
```

## Best Practices

### 1. Preserve Error Visibility
Always ensure that error and warning messages are never filtered. The ExESDB filters follow this principle religiously.

### 2. Filter by Message Content and Metadata
Use both message content and logger metadata to make intelligent filtering decisions:

```elixir
defp should_filter?(level, msg, metadata) do
  cond do
    level in [:error, :warning] -> false
    routine_message?(msg) and routine_module?(metadata) -> true
    true -> false
  end
end
```

### 3. Environment-Specific Configuration
Apply different filtering levels based on your environment:
- **Development**: Minimal filtering for debugging
- **Testing**: Aggressive filtering for clean test output
- **Production**: Balanced filtering for operational visibility

### 4. Monitor Filter Effectiveness
Regularly review your logs to ensure:
- Important messages aren't being filtered
- Noise levels remain manageable
- New components don't introduce new noise patterns

## Filter Performance

Logger filters are applied during log message processing and should be efficient:

- Use pattern matching for quick message classification
- Cache expensive computations where possible
- Prefer string contains checks over regex for performance
- Exit early from filter functions when possible

## Troubleshooting

### Too Much Noise
If you're still seeing too much noise:
1. Check that filters are properly configured
2. Identify new noise sources and extend filters
3. Consider adjusting log levels for specific modules

### Missing Important Messages
If important messages are being filtered:
1. Review filter logic for overly broad patterns
2. Add explicit exceptions for critical message types
3. Test filters in development before production deployment

### Performance Issues
If logging performance is impacted:
1. Profile filter functions for bottlenecks
2. Optimize message matching patterns
3. Consider compile-time filtering for high-volume noise

## Integration with Telemetry

ExESDB's logger filtering integrates well with Phoenix telemetry and observability tools:

```elixir
# Telemetry events are not affected by logger filtering
:telemetry.execute([:exesdb, :stream, :read], %{duration: duration}, %{
  stream_id: stream_id,
  event_count: length(events)
})
```

This ensures that your observability and monitoring systems continue to receive all necessary operational data while keeping logs clean and readable.

## Conclusion

ExESDB's comprehensive logger filtering system provides a clean, production-ready logging experience while maintaining full visibility into system health and errors. By layering BCUtils general-purpose filtering with ExESDB-specific filters, developers get the best of both worlds: quiet logs during normal operation and detailed diagnostics when things go wrong.

The filtering system is designed to be:
- **Intelligent**: Preserves all errors and warnings
- **Comprehensive**: Covers all major noise sources
- **Configurable**: Adaptable to different environments and needs
- **Extensible**: Easy to add custom filters for specific requirements
- **Performant**: Minimal impact on logging performance
