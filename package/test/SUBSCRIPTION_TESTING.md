# Subscription Testing Framework

This document describes the comprehensive testing framework for ExESDB's subscription mechanism, which is crucial for the event sourcing database's functionality.

## Overview

The subscription mechanism in ExESDB is built upon several key components:

1. **Subscriptions Store**: Manages subscription data in Khepri
2. **Stored Procedures**: Khepri triggers that detect subscription changes
3. **EmitterPools**: Supervisors that manage worker processes
4. **EmitterWorkers**: Individual processes that forward events to subscribers
5. **Leadership Management**: Ensures emitter pools run on the Ra leader node

## Test Files

### 1. `subscription_emitter_pools_test.exs`

**Purpose**: Comprehensive testing of the EmitterPool lifecycle and worker management.

**Key Test Areas**:
- Subscription creation triggers EmitterPool start
- EmitterPool starts with correct number of workers
- Workers receive and forward events correctly
- Leadership changes manage EmitterPools properly
- Error handling and worker crash recovery
- Performance under concurrent load

**Usage**:
```bash
# Run all emitter pool tests
mix test test/ex_esdb/subscription_emitter_pools_test.exs

# Run only basic functionality tests
mix test test/ex_esdb/subscription_emitter_pools_test.exs --exclude performance
```

### 2. `subscription_triggers_test.exs`

**Purpose**: Focused testing of Khepri stored procedures and trigger mechanisms.

**Key Test Areas**:
- Trigger function installation and setup
- Create/Update/Delete trigger execution
- Integration with subscription store operations
- Error handling in trigger functions
- Performance under concurrent operations

**Usage**:
```bash
# Run trigger mechanism tests
mix test test/ex_esdb/subscription_triggers_test.exs

# Run only trigger installation tests
mix test test/ex_esdb/subscription_triggers_test.exs -t triggers
```

### 3. `subscription_workflow_integration_test.exs`

**Purpose**: End-to-end integration testing of complete subscription workflows.

**Key Test Areas**:
- Complete event delivery from stream to subscriber
- Subscription state management
- Multiple independent subscriptions
- Error recovery and system resilience
- Performance under high event volume

**Usage**:
```bash
# Run integration tests
mix test test/ex_esdb/subscription_workflow_integration_test.exs

# Run performance tests specifically
mix test test/ex_esdb/subscription_workflow_integration_test.exs -t performance
```

### 4. `support/subscription_test_helpers.ex`

**Purpose**: Shared utilities and helper functions for subscription testing.

**Key Features**:
- Mock subscriber creation and management
- EmitterPool monitoring utilities
- Event generation and validation
- Performance benchmarking tools
- Concurrent operation helpers

## Test Utilities

### Mock Subscribers

The test framework provides sophisticated mock subscribers that can collect events:

```elixir
# Create a mock subscriber
{subscriber_pid, collector_pid} = SubscriptionTestHelpers.create_mock_subscriber()

# Get collected events
events = SubscriptionTestHelpers.get_collected_events(collector_pid)

# Get event count
count = SubscriptionTestHelpers.get_event_count(collector_pid)
```

### EmitterPool Monitoring

Utilities for monitoring EmitterPool lifecycle:

```elixir
# Wait for pool to start
pool_pid = SubscriptionTestHelpers.wait_for_emitter_pool_start(store, sub_topic)

# Health check
{:ok, health_info} = SubscriptionTestHelpers.health_check_emitter_pool(store, sub_topic)

# Kill worker and wait for restart
{:restarted, new_pid} = SubscriptionTestHelpers.kill_and_wait_for_restart(pool_pid, worker_id)
```

### Direct Store Operations

For testing the underlying mechanisms:

```elixir
# Create subscription directly in store
SubscriptionTestHelpers.create_direct_subscription(store, stream_id, subscription_name, subscriber_pid)

# Delete subscription
SubscriptionTestHelpers.delete_direct_subscription(store, stream_id, subscription_name)
```

## Test Configuration

All test suites use similar configuration patterns:

```elixir
@test_opts [
  store_id: :test_store,
  data_dir: "/tmp/test_data_#{:rand.uniform(10000)}",
  timeout: 10_000,
  db_type: :single,
  pub_sub: :test_pubsub,
  reader_idle_ms: 500,
  writer_idle_ms: 500,
  persistence_interval: 1000  # Fast persistence for testing
]
```

## Running Tests

### All Subscription Tests

```bash
# Run all subscription-related tests
mix test test/ex_esdb/subscription*

# Run with coverage
mix test test/ex_esdb/subscription* --cover
```

### Specific Test Categories

```bash
# Basic functionality only
mix test test/ex_esdb/subscription* --exclude performance

# Performance tests only  
mix test test/ex_esdb/subscription* --only performance

# Integration tests only
mix test test/ex_esdb/subscription_workflow_integration_test.exs
```

### Test Output

The tests provide detailed logging:

```
[info] Testing subscription creation triggers emitter pool start
[info] ✅ Successfully verified emitter pool creation
[info] Testing emitter pool starts with correct number of workers
[info] ✅ Successfully verified emitter pool worker structure
```

## Understanding Test Results

### Expected Behaviors

1. **EmitterPool Lifecycle**: Subscriptions should create EmitterPools, which should stop when subscriptions are deleted
2. **Worker Management**: EmitterPools should maintain healthy worker processes that restart on crashes
3. **Event Flow**: Events should flow from streams → triggers → EmitterPools → subscribers
4. **Leadership Awareness**: EmitterPools should only run on Ra leader nodes

### Common Test Scenarios

The tests handle several important scenarios:

1. **Single Node Testing**: Some tests may skip EmitterPool functionality in single-node configurations
2. **Cluster Leadership**: Tests adapt to whether the current node is the cluster leader
3. **Timing Sensitivity**: Tests include appropriate delays for asynchronous operations
4. **Error Recovery**: Tests verify system resilience to worker crashes and invalid data

## Performance Testing

The framework includes performance tests tagged with `@tag :performance`:

### Concurrent Operations
- Tests EmitterPool creation under concurrent subscription operations
- Verifies system stability with multiple simultaneous subscriptions

### High Throughput
- Tests event delivery under high volume
- Measures processing rates and system responsiveness

### Load Testing
- Simulates realistic event sourcing workloads
- Verifies memory usage and process counts remain stable

## Debugging Tests

### Logging

Enable detailed logging during tests:

```elixir
# In test files, increase log level
Logger.configure(level: :debug)

# Or set environment variable
LOG_LEVEL=debug mix test
```

### Process Inspection

The framework provides utilities to inspect system state:

```elixir
# Check EmitterPool health
health_result = SubscriptionTestHelpers.health_check_emitter_pool(store, sub_topic)

# Get worker information
workers = SubscriptionTestHelpers.get_emitter_workers(pool_pid)

# Benchmark operations
benchmark = SubscriptionTestHelpers.benchmark_subscription_operations(store, 10)
```

## Integration with CI/CD

### Test Tags

Tests are organized with appropriate tags:

- `@tag :performance` - Performance-sensitive tests
- Default tests - Core functionality
- Integration tests - End-to-end scenarios

### Configuration for CI

For continuous integration environments:

```elixir
# Shorter timeouts for CI
@test_opts [
  timeout: 5_000,
  persistence_interval: 500,
  reader_idle_ms: 100,
  writer_idle_ms: 100
]
```

## Known Limitations

### Single Node Testing

Some functionality depends on cluster leadership:
- EmitterPools may not start in single-node test configurations
- Leadership-dependent tests include appropriate guards and warnings

### Timing Dependencies

Due to the asynchronous nature of the system:
- Tests include appropriate delays for trigger execution
- Performance tests may show variation based on system load
- Some tests may be sensitive to scheduling delays

### Resource Management

Long-running tests may accumulate:
- Temporary directories (cleaned up in `on_exit`)
- Process registrations (cleaned up automatically)
- Mock processes (explicitly stopped in teardown)

## Contributing to Tests

When adding new subscription features:

1. **Add Unit Tests**: Test individual components in isolation
2. **Add Integration Tests**: Test component interactions
3. **Add Performance Tests**: Verify performance characteristics
4. **Update Helpers**: Add utilities to `SubscriptionTestHelpers` for reuse
5. **Document Behavior**: Update this README with new test scenarios

### Test Structure

Follow the established pattern:

```elixir
describe "Feature Category" do
  test "specific behavior description", context do
    # Arrange
    # Act  
    # Assert
    # Cleanup (if needed)
  end
end
```

### Error Handling

Always handle expected error conditions:

```elixir
case result do
  {:ok, value} ->
    # Test success path
  {:error, reason} ->
    # Handle expected errors gracefully
    Logger.warning("Expected condition occurred: #{inspect(reason)}")
end
```

This comprehensive testing framework ensures the reliability and performance of ExESDB's crucial subscription mechanism, providing confidence in the event sourcing capabilities of the system.
