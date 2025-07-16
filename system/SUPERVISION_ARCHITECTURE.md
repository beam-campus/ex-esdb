# ExESDB Layered Supervision Architecture

## Overview

This document outlines the new layered supervision architecture implemented for ExESDB, which provides better fault tolerance, scalability, and maintainability compared to the previous flat supervision structure.

## Architecture Layout

```
SINGLE NODE MODE:
ExESDB.System (strategy: :rest_for_one)
├── ExESDB.CoreSystem (strategy: :one_for_all)
│   ├── ExESDB.StoreSystem (strategy: :rest_for_one)
│   │   ├── ExESDB.Store (GenServer)
│   │   └── ExESDB.StoreCluster (GenServer)
│   └── ExESDB.PersistenceSystem (strategy: :one_for_one)
│       ├── ExESDB.Streams (Supervisor)
│       ├── ExESDB.Snapshots (Supervisor)
│       └── ExESDB.Subscriptions (Supervisor)
└── ExESDB.GatewaySystem (strategy: :one_for_one)
    ├── PartitionSupervisor (GatewayWorkers)
    └── PubSub (conditional)

CLUSTER MODE:
ExESDB.System (strategy: :rest_for_one)
├── ExESDB.CoreSystem (strategy: :one_for_all)
│   ├── ExESDB.StoreSystem (strategy: :rest_for_one)
│   │   ├── ExESDB.Store (GenServer)
│   │   └── ExESDB.StoreCluster (GenServer)
│   └── ExESDB.PersistenceSystem (strategy: :one_for_one)
│       ├── ExESDB.Streams (Supervisor)
│       ├── ExESDB.Snapshots (Supervisor)
│       └── ExESDB.Subscriptions (Supervisor)
├── LibCluster (for node discovery)
├── ExESDB.LeadershipSystem (strategy: :rest_for_one)
│   ├── ExESDB.LeaderSystem (Supervisor)
│   └── ExESDB.EmitterSystem (Supervisor)
│       └── PartitionSupervisor (EmitterPools)
├── ExESDB.ClusterSystem (cluster coordination)
└── ExESDB.GatewaySystem (strategy: :one_for_one) [STARTS LAST]
    ├── PartitionSupervisor (GatewayWorkers)
    └── PubSub (conditional)
```

## Key Components

### 1. ExESDB.CoreSystem
- **Strategy**: `:one_for_all`
- **Purpose**: Manages critical infrastructure that must restart together
- **Children**: `StoreSystem` and `PersistenceSystem`
- **Rationale**: These components are tightly coupled and must maintain consistency

### 2. ExESDB.StoreSystem
- **Strategy**: `:rest_for_one`
- **Purpose**: Manages store lifecycle and clustering
- **Children**: `Store` and `StoreCluster`
- **Rationale**: `StoreCluster` depends on `Store` being available

### 3. ExESDB.PersistenceSystem
- **Strategy**: `:one_for_one`
- **Purpose**: Manages data persistence components
- **Children**: `Streams`, `Snapshots`, and `Subscriptions`
- **Rationale**: These components operate independently

### 4. ExESDB.LeadershipSystem
- **Strategy**: `:rest_for_one`
- **Purpose**: Manages leader election and event emission
- **Children**: `LeaderSystem` and `EmitterSystem`
- **Rationale**: Event emission depends on leadership being established

### 5. ExESDB.GatewaySystem
- **Strategy**: `:one_for_one`
- **Purpose**: Provides external interface with high availability
- **Children**: `PartitionSupervisor` (for pooled workers) and `PubSub`
- **Rationale**: Components are independent, pooled workers improve fault tolerance

### 6. ExESDB.EmitterSystem
- **Strategy**: `:one_for_one`
- **Purpose**: Manages event emission pools
- **Children**: `PartitionSupervisor` (for dynamic emitter pools)
- **Rationale**: Simple structure for pool management

## Supervision Strategies

### :rest_for_one
Used when child processes have dependencies:
- **ExESDB.System**: Core → Leadership → Gateway dependency chain
- **ExESDB.StoreSystem**: Store → StoreCluster dependency
- **ExESDB.LeadershipSystem**: Leader → Emitter dependency

### :one_for_all
Used when components are tightly coupled:
- **ExESDB.CoreSystem**: Store and persistence must restart together for consistency

### :one_for_one
Used when components are independent:
- **ExESDB.PersistenceSystem**: Streams, snapshots, subscriptions are independent
- **ExESDB.GatewaySystem**: Gateway workers and PubSub are independent
- **ExESDB.EmitterSystem**: Simple pool management

## Improvements Over Previous Architecture

### 1. Better Fault Tolerance
- **Layered isolation**: Failures in one subsystem don't cascade unnecessarily
- **Appropriate restart strategies**: Dependencies are respected while avoiding over-restarts
- **Pooled workers**: Gateway system uses multiple workers instead of a single point of failure

### 2. Improved Scalability
- **Gateway worker pool**: Multiple workers handle requests concurrently
- **Partition supervisors**: Dynamic scaling of emitter and gateway pools
- **Resource isolation**: Critical components are protected from non-critical failures

### 3. Enhanced Maintainability
- **Clear responsibilities**: Each supervisor has a focused purpose
- **Logical grouping**: Related components are grouped together
- **Explicit dependencies**: Restart strategies reflect actual dependencies

### 4. Operational Benefits
- **Selective restarts**: Only affected components restart on failure
- **Reduced downtime**: Critical services can remain available during non-critical failures
- **Better observability**: Clearer supervision tree for debugging
- **Proper startup order**: In cluster mode, core infrastructure starts first, then clustering, then external interface
- **Race condition prevention**: LibCluster starts after core stores are ready, preventing premature node discovery

## Migration Notes

### Deprecated Components
- **ExESDB.GatewaySupervisor**: Replaced by `ExESDB.GatewaySystem`
  - Old: Single `GatewayWorker` with `:one_for_one` strategy
  - New: Pool of `GatewayWorker`s with `PartitionSupervisor`

### Configuration Changes
- **Gateway pool size**: New option `gateway_pool_size` (default: 3)
- **PubSub handling**: Moved from root supervisor to `GatewaySystem`
- **Restart policies**: Tuned for each layer (max_restarts, max_seconds)

## Testing

The layered supervision architecture has been validated through:
1. **Compilation tests**: All modules compile without errors
2. **Child spec validation**: All supervisors have proper child specifications
3. **Integration testing**: System starts up correctly with all layers
4. **Startup verification**: Confirmed all components start in correct order

## Files Modified

1. **system/lib/ex_esdb/system.ex**: Updated to use layered architecture
2. **system/lib/ex_esdb/core_system.ex**: New core infrastructure supervisor
3. **system/lib/ex_esdb/store_system.ex**: New store management supervisor
4. **system/lib/ex_esdb/persistence_system.ex**: New persistence supervisor
5. **system/lib/ex_esdb/leadership_system.ex**: New leadership supervisor
6. **system/lib/ex_esdb/gateway_system.ex**: New gateway supervisor with pooling
7. **system/lib/ex_esdb/emitter_system.ex**: New emitter pool supervisor
8. **system/lib/ex_esdb/gateway_supervisor.ex**: Marked as deprecated

## Future Enhancements

1. **Health System**: Add monitoring and circuit breaker patterns
2. **Metrics Collection**: Integrate observability subsystems
3. **Dynamic Scaling**: Auto-scaling based on load
4. **Circuit Breakers**: Isolate failing components automatically
5. **Graceful Degradation**: Fallback mechanisms for partial failures
