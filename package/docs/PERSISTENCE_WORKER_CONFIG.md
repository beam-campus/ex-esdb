# PersistenceWorker Configuration Guide

## Overview

The enhanced PersistenceWorker now includes comprehensive timeout handling, circuit breaker patterns, backpressure mechanisms, and monitoring capabilities to prevent timeout issues and improve system resilience.

## Configuration Options

### Basic Configuration

```elixir
# In your config/config.exs
config :my_app, :ex_esdb,
  persistence_interval: 5_000,        # Default: 5 seconds
  khepri_timeout: 15_000,             # Default: 15 seconds
  force_persistence_timeout: 30_000,  # Default: 30 seconds
  shutdown_timeout: 15_000,           # Default: 15 seconds
  max_batch_size: 100,                # Default: 100 stores per batch
  max_pending_stores: 1000,           # Default: 1000 max pending stores
  circuit_breaker_failure_threshold: 5, # Default: 5 failures
  circuit_breaker_timeout: 60_000     # Default: 1 minute
```

### Per-Worker Configuration

```elixir
# When starting a worker
opts = [
  store_id: :my_store,
  persistence_interval: 3_000,
  khepri_timeout: 10_000,
  force_persistence_timeout: 25_000,
  max_batch_size: 50,
  circuit_breaker_failure_threshold: 3,
  circuit_breaker_timeout: 30_000
]

{:ok, pid} = ExESDB.PersistenceWorker.start_link(opts)
```

## Timeout Configuration Details

### 1. Khepri Timeout (`khepri_timeout`)
- **Purpose**: Maximum time to wait for a single khepri.fence operation
- **Default**: 15,000ms (15 seconds)
- **Recommendation**: Set based on your disk I/O performance and network latency

### 2. Force Persistence Timeout (`force_persistence_timeout`)
- **Purpose**: Maximum time for `force_persistence/1` GenServer.call
- **Default**: 30,000ms (30 seconds)
- **Recommendation**: Should be larger than khepri_timeout * max_batch_size

### 3. Shutdown Timeout (`shutdown_timeout`)
- **Purpose**: Time allowed for graceful shutdown and final persistence
- **Default**: 15,000ms (15 seconds)
- **Recommendation**: Should be enough to persist all pending stores

### 4. Persistence Interval (`persistence_interval`)
- **Purpose**: How often to run periodic persistence
- **Default**: 5,000ms (5 seconds)
- **Recommendation**: Balance between data durability and performance

## Circuit Breaker Configuration

### Failure Threshold
- **Purpose**: Number of consecutive failures before opening circuit
- **Default**: 5 failures
- **Recommendation**: Adjust based on your system's tolerance for failures

### Circuit Breaker Timeout
- **Purpose**: Time to wait before trying half-open state
- **Default**: 60,000ms (1 minute)
- **Recommendation**: Should allow underlying issues to be resolved

## Backpressure Configuration

### Max Pending Stores
- **Purpose**: Maximum number of stores that can be pending persistence
- **Default**: 1000 stores
- **Recommendation**: Based on your memory constraints and expected load

### Max Batch Size
- **Purpose**: Maximum number of stores to persist in a single batch
- **Default**: 100 stores
- **Recommendation**: Balance between efficiency and timeout risk

## Monitoring and Alerting

### Getting Statistics

```elixir
# Get current statistics
{:ok, stats} = ExESDB.PersistenceWorker.get_stats(:my_store)

# Example output:
%{
  store_id: :my_store,
  total_requests: 1000,
  successful_requests: 950,
  failed_requests: 50,
  circuit_breaker_trips: 2,
  circuit_breaker_state: :closed,
  circuit_breaker_failure_count: 0,
  pending_stores_count: 5,
  average_response_time: 150.5,
  max_response_time: 2000,
  min_response_time: 50,
  last_success_time: 1642123456789,
  last_failure_time: 1642123456000,
  last_persistence_time: 1642123456800,
  uptime: 3600000
}
```

### Circuit Breaker Management

```elixir
# Reset circuit breaker manually
:ok = ExESDB.PersistenceWorker.reset_circuit_breaker(:my_store)
```

## Best Practices

### 1. Timeout Hierarchy
Set timeouts in increasing order:
- `khepri_timeout` < `force_persistence_timeout` < `shutdown_timeout`

### 2. Monitoring
- Monitor circuit breaker state and failure rates
- Alert on high failure rates or circuit breaker trips
- Track average response times for performance trends

### 3. Batch Size Tuning
- Start with default batch size (100)
- Increase if individual operations are fast
- Decrease if operations are slow or memory is limited

### 4. Circuit Breaker Tuning
- Set failure threshold based on your error tolerance
- Adjust timeout based on how long issues typically take to resolve

## Environment Variables

You can also configure via environment variables:

```bash
export PERSISTENCE_INTERVAL=5000
export KHEPRI_TIMEOUT=15000
export FORCE_PERSISTENCE_TIMEOUT=30000
export SHUTDOWN_TIMEOUT=15000
export MAX_BATCH_SIZE=100
export MAX_PENDING_STORES=1000
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
export CIRCUIT_BREAKER_TIMEOUT=60000
```

## Troubleshooting

### Circuit Breaker Open
- Check khepri cluster health
- Verify network connectivity
- Review error logs for underlying issues
- Consider resetting circuit breaker if issue is resolved

### High Response Times
- Check disk I/O performance
- Consider reducing batch size
- Review khepri cluster performance
- Monitor system resources

### Backpressure Warnings
- Increase persistence frequency
- Reduce batch size for faster processing
- Scale horizontally if needed
- Review application persistence request patterns

## Performance Tuning

### High Throughput Systems
```elixir
config :my_app, :ex_esdb,
  persistence_interval: 2_000,          # More frequent persistence
  max_batch_size: 200,                  # Larger batches
  khepri_timeout: 20_000,               # Longer individual timeouts
  force_persistence_timeout: 60_000,    # Much longer for large batches
  max_pending_stores: 5000              # Higher backpressure threshold
```

### High Latency Systems
```elixir
config :my_app, :ex_esdb,
  persistence_interval: 10_000,         # Less frequent persistence
  max_batch_size: 50,                   # Smaller batches
  khepri_timeout: 30_000,               # Longer timeouts for latency
  circuit_breaker_failure_threshold: 10, # More tolerance
  circuit_breaker_timeout: 120_000      # Longer recovery time
```

### Memory Constrained Systems
```elixir
config :my_app, :ex_esdb,
  max_batch_size: 25,                   # Smaller batches
  max_pending_stores: 500,              # Lower backpressure threshold
  persistence_interval: 3_000           # More frequent to reduce pending
```
