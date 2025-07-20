# ExESDB Supervision Tree Diagrams

This document provides comprehensive supervision tree diagrams for ExESDB in both `:single` and `:cluster` startup modes.

## Legend

- **[S]** = Supervisor
- **[GS]** = GenServer
- **[PS]** = PartitionSupervisor
- **[DS]** = DynamicSupervisor
- **[W]** = Worker Process

Strategy abbreviations:
- **one_for_all** = If any child dies, restart all children
- **one_for_one** = Only restart the failed child
- **rest_for_one** = Restart failed child and all children started after it

---

## Single Node Mode (`:single`)

```
ExESDB.System [S] (:rest_for_one)
├── ExESDB.CoreSystem [S] (:one_for_all)
│   ├── ExESDB.PersistenceSystem [S] (:one_for_one)
│   │   ├── ExESDB.Streams [S] (:one_for_one)
│   │   │   ├── ExESDB.StreamsWriters [PS] → DynamicSupervisor pools
│   │   │   └── ExESDB.StreamsReaders [PS] → DynamicSupervisor pools
│   │   ├── ExESDB.Snapshots [S] (:one_for_one)
│   │   │   ├── ExESDB.SnapshotsWriters [PS] → DynamicSupervisor pools
│   │   │   └── ExESDB.SnapshotsReaders [PS] → DynamicSupervisor pools
│   │   └── ExESDB.Subscriptions [S] (:one_for_one)
│   │       ├── ExESDB.SubscriptionsReader [GS]
│   │       └── ExESDB.SubscriptionsWriter [GS]
│   ├── ExESDB.NotificationSystem [S] (:rest_for_one)
│   │   ├── ExESDB.LeaderSystem [S] (:rest_for_one)
│   │   │   ├── ExESDB.LeaderTracker [GS]
│   │   │   └── ExESDB.LeaderWorker [GS]
│   │   └── ExESDB.EmitterSystem [S] (:one_for_one)
│   │       └── ExESDB.EmitterPools [PS] → DynamicSupervisor pools
│   └── ExESDB.StoreSystem [S] (:rest_for_one)
│       ├── ExESDB.Store [GS]
│       ├── ExESDB.StoreCluster [GS]
│       └── ExESDB.StoreRegistry [GS]
└── ExESDB.GatewaySystem [S] (:one_for_one)
    ├── ExESDB.GatewayWorkers [PS] → ExESDB.GatewayWorker pools
    └── PubSub Component [varies]
        ├── ExESDB.PubSub [GS] (if :native)
        └── Phoenix.PubSub [S] (if external pubsub specified)
```

### Key Characteristics - Single Mode:
- **Simpler architecture** with only core functionality
- **GatewaySystem starts immediately** after CoreSystem
- **No clustering components** - minimal overhead
- **Leadership is automatic** - single node is always leader
- **Fast startup** - fewer dependencies

---

## Cluster Mode (`:cluster`)

```
ExESDB.System [S] (:rest_for_one)
├── ExESDB.CoreSystem [S] (:one_for_all)
│   ├── ExESDB.PersistenceSystem [S] (:one_for_one)
│   │   ├── ExESDB.Streams [S] (:one_for_one)
│   │   │   ├── ExESDB.StreamsWriters [PS] → DynamicSupervisor pools
│   │   │   └── ExESDB.StreamsReaders [PS] → DynamicSupervisor pools
│   │   ├── ExESDB.Snapshots [S] (:one_for_one)
│   │   │   ├── ExESDB.SnapshotsWriters [PS] → DynamicSupervisor pools
│   │   │   └── ExESDB.SnapshotsReaders [PS] → DynamicSupervisor pools
│   │   └── ExESDB.Subscriptions [S] (:one_for_one)
│   │       ├── ExESDB.SubscriptionsReader [GS]
│   │       └── ExESDB.SubscriptionsWriter [GS]
│   ├── ExESDB.NotificationSystem [S] (:rest_for_one)
│   │   ├── ExESDB.LeaderSystem [S] (:rest_for_one)
│   │   │   ├── ExESDB.LeaderTracker [GS]
│   │   │   └── ExESDB.LeaderWorker [GS]
│   │   └── ExESDB.EmitterSystem [S] (:one_for_one)
│   │       └── ExESDB.EmitterPools [PS] → DynamicSupervisor pools
│   └── ExESDB.StoreSystem [S] (:rest_for_one)
│       ├── ExESDB.Store [GS]
│       ├── ExESDB.StoreCluster [GS]
│       └── ExESDB.StoreRegistry [GS]
├── LibCluster [S] (external) - Node discovery & connection
├── ExESDB.ClusterSystem [S] (:one_for_one)
│   ├── ExESDB.StoreCoordinator [GS] - Split-brain prevention
│   └── ExESDB.NodeMonitor [GS] - Health monitoring
└── ExESDB.GatewaySystem [S] (:one_for_one) ⚠️ STARTS LAST
    ├── ExESDB.GatewayWorkers [PS] → ExESDB.GatewayWorker pools
    └── PubSub Component [varies]
        ├── ExESDB.PubSub [GS] (if :native)
        └── Phoenix.PubSub [S] (if external pubsub specified)
```

### Key Characteristics - Cluster Mode:
- **Additional clustering layer** after CoreSystem
- **LibCluster handles node discovery** and connection
- **ClusterSystem provides coordination** and split-brain prevention
- **GatewaySystem starts LAST** to ensure clustering is ready
- **Distributed leadership** with automatic failover
- **Higher complexity** but fault-tolerant across nodes

---

## Startup Sequence Analysis

### Single Mode Startup Order:
1. **CoreSystem** (critical foundation)
   - PersistenceSystem (data layer)
   - NotificationSystem (events & leadership)
   - StoreSystem (store lifecycle)
2. **GatewaySystem** (external interface)

### Cluster Mode Startup Order:
1. **CoreSystem** (same as single - critical foundation)
2. **LibCluster** (node discovery and connection)
3. **ClusterSystem** (cluster coordination)
4. **GatewaySystem** (external interface - only after clustering ready)

---

## Critical Design Principles

### 1. Core-First Architecture
- **CoreSystem must be fully operational** before any clustering
- Ensures the store can handle requests before announcing availability
- Prevents race conditions in distributed environments

### 2. Dependency Management
- **:rest_for_one** used where startup order matters
- **:one_for_all** used for tightly coupled components (CoreSystem)
- **:one_for_one** used for independent components

### 3. Fault Tolerance Strategies
- **StoreSystem uses :rest_for_one** - Store → StoreCluster → StoreRegistry
- **NotificationSystem uses :rest_for_one** - LeaderSystem → EmitterSystem
- **PersistenceSystem uses :one_for_one** - independent data components

### 4. Worker Pool Architecture
- **PartitionSupervisor** used for scalable worker pools
- **DynamicSupervisor** provides runtime worker management
- **Gateway pools** provide load distribution and availability

---

## Common Components Detailed

### PersistenceSystem Pool Architecture:
```
Streams/Snapshots → PartitionSupervisor → DynamicSupervisor → Workers
                                       ├── Partition 1 → [Writer Workers]
                                       ├── Partition 2 → [Reader Workers]
                                       └── Partition N → [Worker Pool]
```

### EmitterSystem Pool Architecture:
```
EmitterSystem → EmitterPools (PartitionSupervisor) → DynamicSupervisor → Emitters
                                                  ├── Event Type 1 → [Emitter Workers]
                                                  ├── Event Type 2 → [Emitter Workers]
                                                  └── Event Type N → [Emitter Workers]
```

### GatewaySystem Pool Architecture:
```
GatewaySystem → GatewayWorkers (PartitionSupervisor) → GatewayWorker instances
                                                    ├── Worker 1 → [Request Handler]
                                                    ├── Worker 2 → [Request Handler]
                                                    └── Worker N → [Request Handler]
```

---

## Error Handling & Recovery

### Single Mode Recovery:
- **Simple restart strategies** - minimal cascading failures
- **Fast recovery** due to reduced complexity
- **No coordination overhead** during restarts

### Cluster Mode Recovery:
- **Coordinated restarts** to maintain cluster consistency
- **Leadership reelection** handled automatically
- **Split-brain prevention** via StoreCoordinator
- **Node failure detection** via NodeMonitor

---

## Performance Characteristics

### Single Mode:
- **Fastest startup** - minimal components
- **Lowest memory footprint** - no clustering overhead
- **Direct leadership** - no election process
- **Ideal for development** and small deployments

### Cluster Mode:
- **Distributed fault tolerance** - survives node failures
- **Horizontal scalability** - multiple nodes share load
- **Automatic failover** - seamless leadership transitions
- **Production ready** - handles network partitions

---

This supervision tree architecture provides a robust foundation for ExESDB, with clear separation between core functionality and clustering concerns, ensuring reliable operation in both single-node and distributed environments.
