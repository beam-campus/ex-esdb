# ExESDB Subsystems & Workers Overview

## Architecture Overview

ExESDB uses a reactive, event-driven architecture where all subsystems start in parallel after the ControlSystem and report their readiness via events. Each subsystem supervises its own LoggerWorker for centralized event logging.

## System Hierarchy

```
ExESDB.System (Main Supervisor)
├── ControlSystem (Event coordination infrastructure)
│   ├── ExESDB.PubSub
│   └── ExESDB.ControlPlane
├── PersistenceSystem (Data persistence)
├── NotificationSystem (Event distribution)  
├── StoreSystem (Store lifecycle)
├── ClusterSystem (Node discovery & coordination)
└── GatewaySystem (External interface)
```

## Detailed Subsystem Breakdown

### 1. ControlSystem 
**Purpose**: Event coordination infrastructure (starts first)
**Strategy**: `:one_for_one`

**Components**:
- `ExESDB.PubSub` - Phoenix.PubSub instance for internal events
- `ExESDB.ControlPlane` - Event-driven coordination system

**Events Published**:
- `:system_ready` - When all expected subsystems are ready
- `:initialization_started` - System startup initiated
- `:subsystem_ready` - Individual system readiness reports

---

### 2. PersistenceSystem ⭐ **Updated with LoggerWorker**
**Purpose**: Data persistence layer components
**Strategy**: `:one_for_one` (components are independent)

**Components**:
- ⭐ `ExESDB.LoggerWorker` *(persistence_system)* - Event logging
- `ExESDB.PersistenceWorker` - Asynchronous disk persistence
- `ExESDB.Streams` - Stream read/write operations
- `ExESDB.Snapshots` - Snapshot management  
- `ExESDB.Subscriptions` - Subscription management

**Workers & Pools**:
- `ExESDB.PersistenceWorker` - Main persistence coordination
- `ExESDB.StreamsReaderPool` - Pool of stream readers
- `ExESDB.StreamsWriterPool` - Pool of stream writers  
- `ExESDB.SnapshotsReaderPool` - Pool of snapshot readers
- `ExESDB.SnapshotsWriterPool` - Pool of snapshot writers
- `ExESDB.StreamsReaderWorker` - Individual stream reader
- `ExESDB.StreamsWriterWorker` - Individual stream writer
- `ExESDB.SnapshotsReaderWorker` - Individual snapshot reader
- `ExESDB.SnapshotsWriterWorker` - Individual snapshot writer

**Events Subscribed**: `:system`, `:cluster`, `:leadership`, `:coordination`
**Events Published**: 
- `:events_persisted` - When events are successfully written
- `:persistence_write_started` - Write operation initiated
- `:snapshot_created` - Snapshot completed

---

### 3. NotificationSystem ⭐ **Updated with LoggerWorker**  
**Purpose**: Event notification and distribution
**Strategy**: `:rest_for_one` (EmitterSystem depends on LeaderSystem)

**Components**:
- ⭐ `ExESDB.LoggerWorker` *(notification_system)* - Event logging
- `ExESDB.LeaderSystem` - Leadership responsibilities
- `ExESDB.EmitterSystem` - Event emission and distribution

#### 3a. LeaderSystem
**Components**:
- `ExESDB.LeaderTracker` ⭐ **Reactive** - Observes subscriptions & handles leadership
- `ExESDB.LeaderWorker` - Leadership task execution

**Events Subscribed**: `:leadership`, `:cluster`
**Events Published**:
- `:khepri_leader_changed_received` - Leadership change detected
- `:leader_responsibilities_assumed` - Node became leader
- `:leader_stepping_down` - Node stepping down from leadership
- `:leadership_duties_starting` - Starting leadership tasks
- `:subscriptions_loaded` - Subscriptions retrieved
- `:leadership_duties_assumed` - Leadership fully assumed

#### 3b. EmitterSystem  
**Components**:
- `PartitionSupervisor` managing `ExESDB.EmitterPools`
- Dynamic emitter pools created per subscription

**Workers**:
- `ExESDB.EmitterWorker` - Individual emitter workers
- `ExESDB.EmitterPool` - Pool management for subscriptions

**Events Published**:
- `:emitter_pool_up` - Emitter pool started successfully
- `:emitter_worker_up` - Individual worker ready
- `:notification_triggered` - Subscription notification sent

---

### 4. StoreSystem ⭐ **Updated with LoggerWorker**
**Purpose**: Store lifecycle and clustering coordination  
**Strategy**: `:rest_for_one` (components depend on each other)

**Components**:
- ⭐ `ExESDB.LoggerWorker` *(store_system)* - Event logging
- `ExESDB.Store` - Core store GenServer
- `ExESDB.StoreCluster` - Clustering coordination  
- `ExESDB.StoreRegistry` - Distributed store registry

**Workers**:
- `ExESDB.StoreWorker` - Store operation workers

**Events Subscribed**: `:system`, `:cluster`, `:leadership`, `:coordination`
**Events Published**:
- `:write_command_validated` - Write command validated
- `:write_acknowledged` - Write operation completed
- `:store_synchronization_needed` - Sync required with leader

---

### 5. ClusterSystem
**Purpose**: Cluster coordination and split-brain prevention
**Strategy**: `:one_for_one`

**Components**:
- `ExESDB.StoreCoordinator` - Coordination logic (Khepri-based)
- `ExESDB.NodeMonitor` - Node health monitoring

**Events Published**:
- `:khepri_leader_changed` - Khepri leadership changed
- `:node_discovered` - New node discovered  
- `:cluster_membership_changed` - Membership updated
- `:node_failure_detected` - Node failure detected

**Key Features**:
- Uses Khepri consensus for split-brain prevention
- No data syncing (each node maintains own streams)
- Publishes leadership changes immediately

---

### 6. GatewaySystem
**Purpose**: External interface and API access
**Strategy**: `:one_for_one`

**Components**:
- `PartitionSupervisor` managing `ExESDB.GatewayWorkers`
- Conditional PubSub management

**Workers**:
- `ExESDB.GatewayWorker` - Pool of gateway workers
- `ExESDB.GatewaySupervisor` - Gateway supervision

**Events Published**:
- `:stream_write_requested` - Client write request
- `:subscription_requested` - Client subscription request

---

### Additional Systems (Not in main reactive flow)

#### 7. DebuggingSystem
**Purpose**: Debugging and development tools
**Components**: Various debugging utilities

#### 8. InspectionSystem  
**Purpose**: System inspection and monitoring
**Components**: Inspection utilities

#### 9. MonitoringSystem
**Purpose**: System metrics and health monitoring  
**Components**: Health checkers and metrics collectors

#### 10. ObservationSystem
**Purpose**: System observation and telemetry
**Components**: Metrics collectors and observers

#### 11. ScenarioSystem
**Purpose**: Test scenarios and benchmarking
**Components**: Scenario runners and config loaders

---

## Event-Driven Coordination

### Key Events in Reactive Flow

1. **System Startup**:
   ```
   :system_startup_initiated → :initialization_started → :subsystem_starting → :subsystem_ready → :system_ready
   ```

2. **Leadership Changes**:
   ```  
   :khepri_leader_changed → :khepri_leader_changed_received → :leader_responsibilities_assumed → :subscriptions_loaded → :emitter_pools_starting
   ```

3. **Write Operations**:
   ```
   :stream_write_requested → :write_command_validated → :persistence_write_started → :events_persisted → :write_acknowledged → :notification_triggered
   ```

### LoggerWorker Implementation

Each subsystem now supervises its own LoggerWorker:
- **PersistenceSystem**: LoggerWorker with `subsystem_name: :persistence_system`
- **NotificationSystem**: LoggerWorker with `subsystem_name: :notification_system`  
- **StoreSystem**: LoggerWorker with `subsystem_name: :store_system`

LoggerWorkers subscribe to all event categories:
- `:system` - System lifecycle events
- `:cluster` - Cluster membership events
- `:leadership` - Leadership change events
- `:coordination` - General coordination events

### Event-Driven Coordination Patterns

1. **Direct Event Publishing**:
   - Each subsystem directly publishes lifecycle and state change events via Phoenix.PubSub
   - No intermediary ControlWorker behavior - subsystems publish events directly
   - Events like `:subsystem_ready`, `:subsystem_failure` published immediately
   - Uses shared `ExESDB.PubSub` for internal coordination

2. **LeaderTracker Reactive Behavior** ⭐:
   - Responds immediately to `:khepri_leader_changed` events
   - Delegates to `ExESDB.GatewayAPI` and `ExESDB.Emitters` 
   - Publishes own events for leadership transitions
   - Handles graceful leadership transitions

3. **LoggerWorker Integration**:
   - Each subsystem supervises its own LoggerWorker
   - LoggerWorkers subscribe to control plane events related to the subsystem
   - Provides centralized logging without polluting upstream modules
   - No direct `IO.puts` or `Logger` calls in business logic

### Benefits

1. **Faster Startup**: Parallel system initialization
2. **Better Fault Tolerance**: Event-driven coordination resilient to failures  
3. **Centralized Logging**: All events logged via dedicated LoggerWorkers
4. **Better Observability**: Rich event stream for monitoring
5. **No Split-Brain**: Khepri consensus prevents cluster split-brain scenarios
6. **Graceful Leadership**: Emitter pools transition gracefully on leadership change

### Next Implementation Steps

1. ✅ **LoggerWorker** - Created and integrated in key subsystems
2. ✅ **Reactive LeaderTracker** - Handles `:khepri_leader_changed` immediately  
3. 🔄 **Emitters Module Updates** - Add leadership assumption/step-down functions
4. 🔄 **GatewayAPI Integration** - Ensure list_subscriptions works with LeaderTracker
5. 🔄 **Event Schema Definitions** - Formalize event structures
6. 🔄 **Integration Tests** - End-to-end reactive behavior tests

---

*This document reflects the current reactive architecture implementation. Systems marked with ⭐ have been updated with the new event-driven patterns.*
