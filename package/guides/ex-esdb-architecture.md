# ExESDB Architecture Analysis

## Overview

ExESDB is a BEAM-native Event Store built on top of the Khepri library, which in turn is built on the Ra library. It's designed as a distributed, fault-tolerant event sourcing system that leverages the strengths of the BEAM ecosystem for handling concurrent, distributed workloads.

## High-Level Architecture

```mermaid
graph TD
    A[ExESDB.App] --> B[ExESDB.System]
    B --> C[PubSub Layer]
    B --> D[Store Management]
    B --> E[Cluster Management]
    B --> F[Event Processing]
    B --> G[Gateway Layer]
    
    D --> D1[StoreManager]
    D --> D2[Store Workers]
    D --> D3[Khepri Backend]
    
    E --> E1[LibCluster]
    E --> E2[ClusterSystem]
    E --> E3[KhepriCluster]
    E --> E4[LeaderSystem]
    
    F --> F1[Streams]
    F --> F2[Snapshots]
    F --> F3[Subscriptions]
    
    G --> G1[GatewaySupervisor]
    G --> G2[GatewayWorker]
```

## Core Components

### 1. Application Layer

#### ExESDB.App
- **Purpose**: Main application entry point
- **Responsibilities**:
  - Application lifecycle management
  - Initial configuration loading
  - Starting the main supervisor tree
  - Graceful shutdown handling

#### ExESDB.System
- **Purpose**: Top-level supervisor for the entire system
- **Responsibilities**:
  - Supervises all major subsystems
  - Manages system startup sequence
  - Handles OS signal processing
  - Dynamically configures components based on deployment mode (single vs cluster)

### 2. Storage Layer

#### ExESDB.StoreManager
- **Purpose**: Multi-store management and coordination
- **Responsibilities**:
  - Dynamic store creation and removal
  - Store lifecycle management
  - Configuration management per store
  - Store status tracking

#### ExESDB.Store
- **Purpose**: Individual event store wrapper around Khepri
- **Responsibilities**:
  - Khepri store initialization
  - Store state management
  - Direct interaction with Khepri API

```mermaid
graph LR
    A[StoreManager] --> B[Store1]
    A --> C[Store2]
    A --> D[StoreN]
    
    B --> E[Khepri Instance 1]
    C --> F[Khepri Instance 2]
    D --> G[Khepri Instance N]
    
    E --> H[Data Directory 1]
    F --> I[Data Directory 2]
    G --> J[Data Directory N]
```

### 3. Clustering Layer

The clustering layer provides distributed coordination and fault tolerance:

#### ExESDB.KhepriCluster
- **Purpose**: Khepri-specific cluster coordination
- **Responsibilities**:
  - Cluster join/leave operations
  - Leadership detection and tracking
  - Membership monitoring
  - Node health monitoring

#### ExESDB.ClusterSystem
- **Purpose**: High-level cluster coordination
- **Responsibilities**:
  - Supervises cluster coordination components
  - Manages cluster-specific services
  - Handles split-brain prevention

#### ExESDB.LeaderSystem
- **Purpose**: Leadership management
- **Responsibilities**:
  - Leader election coordination
  - Leader-specific functionality activation
  - Leader state tracking

```mermaid
graph TD
    A[LibCluster] --> B[Node Discovery]
    B --> C[KhepriCluster]
    C --> D[Cluster Join/Leave]
    C --> E[Leadership Detection]
    C --> F[Membership Monitoring]
    
    G[ClusterSystem] --> H[ClusterCoordinator]
    G --> I[NodeMonitor]
    
    J[LeaderSystem] --> K[LeaderWorker]
    J --> L[LeaderTracker]
    
    style A fill:#e1f5fe
    style G fill:#f3e5f5
    style J fill:#e8f5e8
```

### 4. Event Processing Layer

#### ExESDB.Streams
- **Purpose**: Event stream management
- **Responsibilities**:
  - Stream read/write operations
  - Stream partitioning via PartitionSupervisor
  - Worker pool management for stream operations

#### ExESDB.Snapshots
- **Purpose**: Snapshot management for event sourcing
- **Responsibilities**:
  - Snapshot creation and retrieval
  - Snapshot versioning
  - Snapshot storage path management

#### ExESDB.Subscriptions
- **Purpose**: Event subscription management
- **Responsibilities**:
  - Subscription lifecycle management
  - Event delivery to subscribers
  - Subscription persistence

```mermaid
graph TD
    A[Streams] --> B[StreamsWriters Pool]
    A --> C[StreamsReaders Pool]
    
    D[Snapshots] --> E[SnapshotsWriters Pool]
    D --> F[SnapshotsReaders Pool]
    
    G[Subscriptions] --> H[SubscriptionsReader]
    G --> I[SubscriptionsWriter]
    
    B --> J[DynamicSupervisor]
    C --> K[DynamicSupervisor]
    E --> L[DynamicSupervisor]
    F --> M[DynamicSupervisor]
    
    J --> N[StreamWriterWorker1]
    J --> O[StreamWriterWorker2]
    K --> P[StreamReaderWorker1]
    K --> Q[StreamReaderWorker2]
```

### 5. Communication Layer

#### PubSub Integration
- **Purpose**: Inter-process and inter-node communication
- **Responsibilities**:
  - Event broadcasting
  - Subscription management
  - Message routing

#### ExESDB.GatewaySupervisor & GatewayWorker
- **Purpose**: External API gateway
- **Responsibilities**:
  - External client request handling
  - API endpoint management
  - Request routing to appropriate subsystems

## Architecture Patterns

### 1. Supervision Tree Pattern

```mermaid
graph TD
    A[ExESDB.App] --> B[ExESDB.System]
    B --> C[PubSub]
    B --> D[StoreManager]
    B --> E[Streams]
    B --> F[Snapshots]
    B --> G[Subscriptions]
    B --> H[LeaderSystem]
    B --> I[KhepriCluster]
    B --> J[GatewaySupervisor]
    B --> K[ClusterSystem]
    B --> L[EmitterPools]
    
    E --> M[PartitionSupervisor - Writers]
    E --> N[PartitionSupervisor - Readers]
    
    F --> O[PartitionSupervisor - Writers]
    F --> P[PartitionSupervisor - Readers]
    
    H --> Q[LeaderWorker]
    H --> R[LeaderTracker]
    
    K --> S[ClusterCoordinator]
    K --> T[NodeMonitor]
    
    J --> U[GatewayWorker]
```

### 2. Worker Pool Pattern

ExESDB extensively uses worker pools for different types of operations:

```mermaid
graph LR
    A[Client Request] --> B[PartitionSupervisor]
    B --> C[DynamicSupervisor]
    C --> D[Worker1]
    C --> E[Worker2]
    C --> F[WorkerN]
    
    G[Hash Ring] --> B
    H[Load Balancing] --> B
```

### 3. Distributed State Management

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Gateway
    participant L as Leader
    participant F as Follower
    participant K as Khepri
    
    C->>G: Write Request
    G->>L: Route to Leader
    L->>K: Write to Khepri
    K->>F: Replicate to Followers
    F->>K: Acknowledge
    K->>L: Confirm Write
    L->>G: Success Response
    G->>C: Return Result
```

## Deployment Modes

### Single Node Mode
- **Configuration**: `db_type: :single`
- **Characteristics**:
  - No clustering components
  - Local-only operations
  - Simplified architecture
  - Development/testing focused

### Cluster Mode
- **Configuration**: `db_type: :cluster`
- **Characteristics**:
  - Full clustering capabilities
  - Distributed consensus via Ra
  - Fault tolerance
  - Production-ready

```mermaid
graph TD
    A[Configuration] --> B{db_type}
    B -->|:single| C[Single Node Components]
    B -->|:cluster| D[Cluster Components]
    
    C --> E[StoreManager]
    C --> F[Local Streams]
    C --> G[Local Snapshots]
    
    D --> H[LibCluster]
    D --> I[ClusterSystem]
    D --> J[KhepriCluster]
    D --> K[Distributed Components]
```

## Data Flow

### Event Write Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant GW as Gateway
    participant SM as StoreManager
    participant S as Store
    participant K as Khepri
    participant PS as PubSub
    
    C->>GW: Write Event
    GW->>SM: Route to Store
    SM->>S: Write Request
    S->>K: Store Event
    K->>S: Confirm Write
    S->>PS: Publish Event
    PS->>C: Event Notification
    S->>GW: Success Response
    GW->>C: Return Result
```

### Event Read Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant GW as Gateway
    participant SR as StreamReader
    participant S as Store
    participant K as Khepri
    
    C->>GW: Read Stream
    GW->>SR: Route to Reader
    SR->>S: Read Request
    S->>K: Query Events
    K->>S: Return Events
    S->>SR: Event Data
    SR->>GW: Stream Response
    GW->>C: Return Events
```

## Key Design Decisions

### 1. Khepri as Backend
- **Rationale**: BEAM-native, Ra-based distributed database
- **Benefits**: 
  - Native Erlang integration
  - Built-in clustering
  - Strong consistency guarantees
  - Fault tolerance

### 2. Supervisor Tree Architecture
- **Rationale**: Leverages OTP supervision principles
- **Benefits**:
  - Fault isolation
  - Automatic restart strategies
  - System resilience
  - Clear responsibility boundaries

### 3. Worker Pool Pattern
- **Rationale**: Efficient concurrent processing
- **Benefits**:
  - Load distribution
  - Resource management
  - Scalability
  - Fault tolerance

### 4. Multi-Store Architecture
- **Rationale**: Support for multiple event stores in single cluster
- **Benefits**:
  - Tenant isolation
  - Resource optimization
  - Flexible deployment
  - Gradual migration support

## Performance Considerations

### Partitioning Strategy
- Uses PartitionSupervisor for distributing workload
- Hash-based routing for even distribution
- Separate pools for read/write operations

### Clustering Optimization
- Configurable probe intervals for node monitoring
- Failure thresholds to prevent cascade failures
- Efficient membership change detection

### Resource Management
- Dynamic worker creation/destruction
- Configurable timeout values
- Memory-efficient event storage via Khepri

## Security Considerations

### Network Security
- Node-to-node communication via Erlang distribution
- Cluster authentication via shared secrets
- Network partitioning detection and handling

### Access Control
- Gateway-based request filtering
- Store-level access control
- Subscription-based permissions

## Monitoring and Observability

### Metrics Collection
- Built-in metrics module
- Performance monitoring
- Cluster health tracking

### Logging Strategy
- Structured logging throughout
- Configurable log levels
- Cluster-aware log correlation

### Health Checks
- Node health monitoring
- Store availability checks
- Leadership status tracking

## Scalability Patterns

### Horizontal Scaling
- Add nodes to existing cluster
- Automatic workload redistribution
- Leader election for coordination

### Vertical Scaling
- Worker pool sizing
- Memory allocation tuning
- Timeout configuration

This architecture provides a solid foundation for building distributed, fault-tolerant event sourcing systems while leveraging the unique strengths of the BEAM ecosystem.
