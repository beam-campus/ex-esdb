# ExESDB.Debugger

A comprehensive debugging and inspection tool for ExESDB Event Sourcing Database systems.

## Overview

The ExESDB Debugger provides REPL-friendly functions to investigate all aspects of your ExESDB system, including:

- 🔍 **Process Supervision Tree Inspection**
- ⚙️ **Configuration Analysis**
- 📊 **Stream and Event Investigation**  
- 📈 **Performance Metrics**
- 🏥 **Health Monitoring**
- 🔄 **Emitter Pool Management**
- 🔬 **Function Tracing**
- ⏱️ **Benchmarking Tools**

## Quick Start

```elixir
# In your IEx session
iex> ExESDB.Debugger.overview()
iex> ExESDB.Debugger.help()
```

## Core Functions

### System Overview
```elixir
# Get a complete system overview
ExESDB.Debugger.overview()
ExESDB.Debugger.overview(:my_store)

# Show help with all available commands
ExESDB.Debugger.help()
```

### Process Management
```elixir
# List all ExESDB processes
ExESDB.Debugger.processes()

# Display supervision tree
ExESDB.Debugger.supervision_tree()

# Show emitter pools and workers
ExESDB.Debugger.emitters()
```

### Configuration
```elixir
# Show detailed configuration
ExESDB.Debugger.config()

# Configuration shows sources (app config vs environment variables)
```

### Data Investigation
```elixir
# List all streams
ExESDB.Debugger.streams()

# Show events in a specific stream
ExESDB.Debugger.events("user-123", limit: 10)
ExESDB.Debugger.events("orders", start_version: 50, direction: :backward)

# List active subscriptions
ExESDB.Debugger.subscriptions()
```

### Health & Performance
```elixir
# Comprehensive health check
ExESDB.Debugger.health()

# Performance metrics
ExESDB.Debugger.performance()

# Show top processes by memory/CPU
ExESDB.Debugger.top()
ExESDB.Debugger.top(limit: 5, sort_by: :reductions)
```

### Debugging Tools
```elixir
# Start Erlang Observer GUI
ExESDB.Debugger.observer()

# Trace function calls
ExESDB.Debugger.trace(ExESDB.StreamsWriter, :append_events, duration: 5000)

# Benchmark functions
ExESDB.Debugger.benchmark(fn -> expensive_operation() end, times: 100)
```

## Multi-Store Support

All functions work with multiple stores:

```elixir
# Auto-discover the store (works with single stores)
ExESDB.Debugger.overview()

# Specify a particular store
ExESDB.Debugger.overview(:orders_store)
ExESDB.Debugger.processes(:inventory_store)
ExESDB.Debugger.health(:users_store)
```

## Example Output

### System Overview
```
🔍 ExESDB System Overview
========================================
📊 Store: :my_store
🔧 System: ✅ Running
🆔 PID: #PID<0.1234.0>
🌐 Node: :node@localhost
✅ System healthy
⚙️  Processes: 12/12 alive
⚙️  Config: cluster mode, data: /tmp/data

💡 Use ExESDB.Debugger.help() for available commands
```

### Health Check
```
🏥 ExESDB Health Check for :my_store
==================================================
✅ System Process       : OK
✅ Configuration        : OK
✅ Gateway Workers      : 2 gateway worker(s) running
✅ Store Accessibility  : OK
⚠️ Memory Usage        : High memory usage: 156.7 MB
✅ Process Supervision  : OK

📊 Summary: 6 checks, 0 errors, 1 warnings
```

### Process Listing
```
⚙️  ExESDB Processes for :my_store
==================================================

📦 System (1 processes)
  ✅ exesdb_system_my_store         #PID<0.1234.0> 2.1MB msgs:0

📦 Gateway (2 processes)  
  ✅ gateway_worker_my_store_1      #PID<0.1235.0> 1.2MB msgs:0
  ✅ gateway_worker_my_store_2      #PID<0.1236.0> 1.1MB msgs:0

📦 Emitter (3 processes)
  ✅ emitter_pool_subscription_1    #PID<0.1237.0> 512KB msgs:0

📊 Total Memory: 4.8MB
```

## Health Checks

The health check performs the following validations:

- ✅ **System Process**: Main supervisor is running
- ✅ **Configuration**: All config values are accessible
- ✅ **Gateway Workers**: At least one gateway worker is available
- ✅ **Store Accessibility**: Can communicate with the store
- ⚠️ **Memory Usage**: Monitors total memory consumption
- ✅ **Process Supervision**: All supervised processes are alive

## Performance Monitoring

```elixir
ExESDB.Debugger.performance()
```

Shows:
- System memory and CPU info
- Total ExESDB process count and memory usage
- Top memory-consuming processes
- System uptime

## Tracing and Debugging

### Function Tracing
```elixir
# Trace all calls to a function for 5 seconds
ExESDB.Debugger.trace(ExESDB.StreamsWriter, :append_events)

# Custom tracing duration
ExESDB.Debugger.trace(MyModule, :my_function, duration: 10_000)
```

### Benchmarking
```elixir
# Benchmark a function
ExESDB.Debugger.benchmark(fn -> 
  ExESDB.StreamsWriter.append_events(:my_store, "test", [%{type: "test"}])
end, times: 100)
```

### Observer GUI
```elixir
# Opens the Erlang Observer for real-time monitoring
ExESDB.Debugger.observer()
```

## Dependencies

The debugger uses several built-in and external libraries:

- **:recon** - Process inspection and system information
- **:observer** - Erlang Observer GUI (included in OTP)
- **:dbg** - Function tracing (included in OTP)
- **:sys** - System process inspection (included in OTP)

## Troubleshooting

### Common Issues

1. **No processes found**
   ```elixir
   # Make sure ExESDB is running
   ExESDB.Debugger.health()  # Will show what's missing
   ```

2. **Gateway worker not available**
   ```elixir
   # Check if the system is properly started
   ExESDB.Debugger.supervision_tree()
   ```

3. **Memory warnings**
   ```elixir
   # Investigate top memory consumers
   ExESDB.Debugger.top(sort_by: :memory)
   ExESDB.Debugger.observer()  # For detailed analysis
   ```

### Tips

- Use `help()` to see all available commands
- All functions work without store_id (auto-discovery)
- Health checks will identify most common issues
- Observer GUI provides real-time monitoring
- Tracing is helpful for performance debugging
- Performance monitoring shows system resource usage

## Integration

The debugger is designed to be used in development and production REPL sessions. It's safe to use in production as all operations are read-only by default.

Add it to your application by ensuring ExESDB is in your dependencies, then use it directly in IEx:

```elixir
# In your IEx session after starting your app
iex> ExESDB.Debugger.overview()
```

## Examples

### Development Workflow
```elixir
# 1. Start your app
iex -S mix

# 2. Check system health
ExESDB.Debugger.health()

# 3. Look at your data
ExESDB.Debugger.streams()
ExESDB.Debugger.events("user-123", limit: 5)

# 4. Monitor performance
ExESDB.Debugger.performance()
ExESDB.Debugger.top()

# 5. Debug issues
ExESDB.Debugger.trace(MyModule, :problematic_function)
```

### Production Debugging
```elixir
# Quick health check
ExESDB.Debugger.health()

# Check memory usage
ExESDB.Debugger.performance()

# Investigate specific issues
ExESDB.Debugger.processes()
ExESDB.Debugger.supervision_tree()
```

The ExESDB Debugger makes it easy to understand, monitor, and debug your Event Sourcing system!
