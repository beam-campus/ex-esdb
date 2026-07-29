# ExESDB - A BEAM-native Event Store
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://buymeacoffee.com/rlefever)

`ExESDB` is a BEAM-native Event Store, built on top of the [khepri](https://github.com/rabbitmq/khepri) and [ra](https://github.com/rabbitmq/ra) subsystems.

## Motivation

One of the arguments for BEAM development is that it comes "batteries included". Be it caching, storage, pub/sub, observability etc... the Erlang ecosystem always has the option to avoid external dependencies.

For Event Sourcing use cases however, the Event Store is often a separate service.

This project is an attempt at addressing this point, by building further upon the work of the `rabbitmq/khepri` and `rabbitmq/ra` subsystems.

## Features

ExESDB is a distributed, BEAM-native Event Store that provides high-availability event sourcing capabilities with automatic cluster formation and coordination. Built on top of Khepri and Ra (Raft consensus), it offers enterprise-grade reliability and performance.

### Core Event Store Functionality

#### Event Stream Management
- **Stream Creation**: Automatic stream creation on first event append
- **Event Appending**: Atomic append operations with optimistic concurrency control
- **Event Retrieval**: Query events with forward/backward traversal support
- **Stream Versioning**: Track stream versions for conflict detection and resolution
- **Stream Listing**: Enumerate all streams in the store

#### Event Storage
- **Persistent Storage**: Durable event storage using Khepri's distributed key-value store
- **ACID Compliance**: Atomic, consistent, isolated, and durable operations
- **Conflict Resolution**: Built-in optimistic concurrency control
- **Data Integrity**: Checksum validation and corruption detection

#### Subscription System
- **Multiple Subscription Types**:
  - `:by_stream` - Subscribe to specific event streams
  - `:by_event_type` - Subscribe to events by type classification
  - `:by_event_pattern` - Pattern-based event matching
  - `:by_event_payload` - Content-based subscription filtering
- **Persistent Subscriptions**: Durable subscriptions that survive node restarts
- **Transient Subscriptions**: Temporary subscriptions for real-time processing
- **Event Replay**: Start subscriptions from any stream version
- **Acknowledgment System**: Reliable event delivery with ACK/NACK support
- **"Follow-the-Leader"**: Subscription processes automatically migrate to cluster leader

#### Snapshot Management
- **Aggregate Snapshots**: Store and retrieve aggregate state snapshots
- **Version-based Snapshots**: Snapshots tied to specific stream versions
- **Snapshot Lifecycle**: Create, read, update, and delete snapshot operations
- **Performance Optimization**: Reduce replay time for large aggregates
- **Distributed Storage**: Snapshots stored across the cluster for availability

### Distributed Architecture & Clustering

#### LibCluster Integration
ExESDB uses LibCluster for automatic cluster discovery and formation:

- **Strategy**: Gossip-based multicast discovery
- **Protocol**: UDP multicast on configurable port (default: 45892)
- **Network**: Automatic node discovery on shared networks
- **Security**: Shared secret authentication for cluster membership
- **Broadcast Discovery**: Configurable multicast addressing

#### Cluster Formation Process
1. **Initialization**: Node starts and initializes LibCluster topology
2. **Discovery**: Uses gossip multicast to discover peer nodes
3. **Authentication**: Validates cluster membership using shared secrets
4. **Coordination**: ClusterCoordinator manages join/leave operations
5. **Consensus**: Khepri cluster formation using Raft consensus
6. **Monitoring**: Continuous health monitoring and leader election

#### High Availability Features
- **Automatic Clustering**: Nodes automatically discover and join clusters
- **Split-Brain Prevention**: ClusterCoordinator prevents network partition issues
- **Leader Election**: Automatic leader election using Raft consensus
- **Failover**: Seamless handling of node failures
- **Data Replication**: Events replicated across cluster nodes
- **Consensus Protocol**: Ra/Raft ensures data consistency

### Storage Engine

#### Khepri Integration
- **Distributed Tree Store**: Hierarchical key-value storage
- **MVCC**: Multi-version concurrency control
- **Transactions**: ACID transaction support
- **Schema Evolution**: Support for data structure changes
- **Triggers**: Event-driven data processing

#### Ra (Raft) Consensus
- **Strong Consistency**: Linearizable read/write operations
- **Partition Tolerance**: Operates correctly during network partitions
- **Leader-based Replication**: Single leader for write operations
- **Log Compaction**: Automatic cleanup of old log entries
- **Snapshot Support**: Efficient state transfer for new nodes

### Configuration & Deployment

#### Environment Configuration
- `EX_ESDB_STORE_ID`: Unique identifier for the store instance
- `EX_ESDB_DB_TYPE`: Deployment type (`:single` or `:cluster`)
- `EX_ESDB_DATA_DIR`: Data directory for persistent storage
- `EX_ESDB_TIMEOUT`: Operation timeout configuration
- `EX_ESDB_CLUSTER_SECRET`: Shared secret for cluster authentication
- `EX_ESDB_COOKIE`: Erlang distribution cookie
- `EX_ESDB_PUB_SUB`: PubSub configuration for event broadcasting

#### LibCluster Configuration
```elixir
config :libcluster,
  topologies: [
    ex_esdb_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45_892,
        if_addr: "0.0.0.0",
        multicast_addr: "255.255.255.255",
        broadcast_only: true,
        secret: System.get_env("EX_ESDB_CLUSTER_SECRET")
      ]
    ]
  ]
```

### Gateway API Integration

#### High-Availability Proxy
- **Load Balancing**: Distribute requests across gateway workers
- **Service Discovery**: Automatic discovery of available gateway workers
- **Fault Tolerance**: Handle worker failures gracefully
- **Request Routing**: Smart routing based on operation type

#### Worker Distribution
- **Swarm Integration**: Distributed worker management
- **Process Migration**: Workers can move between cluster nodes
- **Resource Management**: Efficient resource utilization across cluster
- **Monitoring**: Real-time worker health and performance tracking

### Operational Features

#### Monitoring & Observability
- **Cluster Status**: Real-time cluster membership and health
- **Leader Tracking**: Monitor current cluster leader
- **Performance Metrics**: Operation latency and throughput
- **Error Tracking**: Comprehensive error logging and reporting
- **Health Checks**: Built-in health check endpoints

#### Development Tools
- **Cluster Manager**: Interactive cluster management script
- **Docker Compose**: Multi-node development environment
- **Chaos Engineering**: Built-in chaos testing capabilities
- **Validation Scripts**: Automated cluster validation tools

### Network Topology

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ExESDB Node   │    │   ExESDB Node   │    │   ExESDB Node   │
│    (Leader)     │◄──►│   (Follower)    │◄──►│   (Follower)    │
│   Khepri + Ra   │    │   Khepri + Ra   │    │   Khepri + Ra   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         │     Gossip Multicast Network (UDP:45892)     │
         │                       │                       │
         ▼                       ▼                       ▼
    Raft Consensus           Event Storage           Subscription
     & Replication          & Retrieval             Management
```

### Deployment Scenarios

#### Single Node Deployment
- **Development**: Local development and testing
- **Small Applications**: Simple event sourcing needs
- **Embedded Usage**: Integration within existing applications

#### Multi-Node Cluster
- **Production**: High-availability production deployments
- **Horizontal Scaling**: Scale read/write capacity
- **Geographic Distribution**: Multi-region deployments
- **Fault Tolerance**: Survive individual node failures

#### Container Orchestration
- **Docker Compose**: Development and testing environments
- **Kubernetes**: Production container orchestration
- **Docker Swarm**: Simplified container clustering
- **Health Checks**: Container-level health monitoring

### Performance Characteristics

#### Throughput
- **Write Performance**: Optimized for high-volume event appending
- **Read Performance**: Efficient event retrieval and streaming
- **Concurrent Operations**: Handle multiple simultaneous operations
- **Batch Processing**: Support for batch event operations

#### Scalability
- **Horizontal Scaling**: Add nodes to increase capacity
- **Storage Scalability**: Distributed storage across cluster
- **Subscription Scaling**: Distribute subscription load
- **Resource Utilization**: Efficient use of available resources

### Integration Capabilities

#### BEAM Ecosystem
- **Phoenix Integration**: Real-time web applications
- **LiveView Support**: Real-time UI updates
- **GenServer Integration**: Native BEAM process integration
- **OTP Supervision**: Fault-tolerant supervision trees

#### External Systems
- **REST APIs**: HTTP-based integration
- **Message Queues**: Integration with external queuing systems
- **Databases**: Projection and read model support
- **Monitoring Systems**: Metrics and alerting integration

## Installation

### Docker Installation

ExESDB is available as a Docker image on Docker Hub with automatic versioning based on the `mix.exs` version.

#### Available Tags
- `beamcampus/ex_esdb:latest` - Latest build from master branch
- `beamcampus/ex_esdb:0.0.18` - Specific version (current version)
- `beamcampus/ex_esdb:0.0.x` - Any specific version tag

#### Quick Start

**Single Node:**
```bash
docker run -d \
  --name ex-esdb \
  -p 4369:4369 \
  -p 9000-9100:9000-9100 \
  -p 45892:45892/udp \
  -e EX_ESDB_STORE_ID="my-store" \
  -e EX_ESDB_DB_TYPE="single" \
  -e EX_ESDB_DATA_DIR="/data" \
  -v ex-esdb-data:/data \
  beamcampus/ex_esdb:latest
```

**Multi-Node Cluster:**
```bash
# Node 1 (seed node)
docker run -d \
  --name ex-esdb-node1 \
  --network ex-esdb-net \
  -p 4369:4369 \
  -p 9001:9000 \
  -p 45892:45892/udp \
  -e EX_ESDB_STORE_ID="cluster-store" \
  -e EX_ESDB_DB_TYPE="cluster" \
  -e EX_ESDB_DATA_DIR="/data" \
  -e EX_ESDB_CLUSTER_SECRET="your-secret-key" \
  -e EX_ESDB_COOKIE="your-erlang-cookie" \
  -v ex-esdb-node1-data:/data \
  beamcampus/ex_esdb:latest

# Node 2
docker run -d \
  --name ex-esdb-node2 \
  --network ex-esdb-net \
  -p 9002:9000 \
  -e EX_ESDB_STORE_ID="cluster-store" \
  -e EX_ESDB_DB_TYPE="cluster" \
  -e EX_ESDB_DATA_DIR="/data" \
  -e EX_ESDB_CLUSTER_SECRET="your-secret-key" \
  -e EX_ESDB_COOKIE="your-erlang-cookie" \
  -v ex-esdb-node2-data:/data \
  beamcampus/ex_esdb:latest

# Node 3
docker run -d \
  --name ex-esdb-node3 \
  --network ex-esdb-net \
  -p 9003:9000 \
  -e EX_ESDB_STORE_ID="cluster-store" \
  -e EX_ESDB_DB_TYPE="cluster" \
  -e EX_ESDB_DATA_DIR="/data" \
  -e EX_ESDB_CLUSTER_SECRET="your-secret-key" \
  -e EX_ESDB_COOKIE="your-erlang-cookie" \
  -v ex-esdb-node3-data:/data \
  beamcampus/ex_esdb:latest
```

#### Docker Compose

For development and testing, use the provided Docker Compose setup:

```bash
# Clone the repository
git clone https://github.com/beam-campus/ex-esdb.git
cd ex-esdb/dev-env

# Start a 3-node cluster
./start-core-only.sh

# Or use the interactive cluster manager
./ez-cluster.sh
```

The Docker Compose setup includes:
- **Core Cluster**: 3-node ExESDB cluster (ex-esdb0, ex-esdb1, ex-esdb2)
- **Extended Tier**: Additional 2 nodes (ex-esdb10, ex-esdb11)
- **Massive Tier**: Additional 8 nodes (ex-esdb20-27)
- **Automatic Networking**: Configured Docker networks for cluster communication
- **Data Persistence**: Named volumes for data persistence
- **Health Checks**: Built-in container health monitoring

#### Environment Variables

> **📌 Important**: When using the dev-env Docker Compose configurations, you must export the `EX_ESDB_COOKIE` environment variable on your host machine. This single environment variable is used for all cluster authentication purposes (cookies, secrets, etc.).
> 
> ```bash
> export EX_ESDB_COOKIE="your-secure-cookie-value"
> ```

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `EX_ESDB_STORE_ID` | Unique store identifier | - | Yes |
| `EX_ESDB_DB_TYPE` | Deployment type (`single` or `cluster`) | `single` | No |
| `EX_ESDB_DATA_DIR` | Data directory path | `/data` | No |
| `EX_ESDB_TIMEOUT` | Operation timeout (ms) | `5000` | No |
| `EX_ESDB_CLUSTER_SECRET` | Cluster authentication secret | - | Yes (cluster) |
| `EX_ESDB_COOKIE` | Erlang distribution cookie | - | Yes (cluster) |
| `EX_ESDB_PUB_SUB` | PubSub process name | `:ex_esdb_pubsub` | No |

#### Ports

| Port | Protocol | Description |
|------|----------|-------------|
| `4369` | TCP | EPMD (Erlang Port Mapper Daemon) |
| `9000-9100` | TCP | Erlang distribution ports |
| `45892` | UDP | LibCluster gossip multicast |

#### Health Checks

The Docker image includes a built-in health check script:

```bash
# Check container health
docker exec ex-esdb ./check-ex-esdb.sh

# View health status
docker inspect --format='{{.State.Health.Status}}' ex-esdb
```

#### Production Considerations

1. **Security**: Use strong, unique values for `EX_ESDB_CLUSTER_SECRET` and `EX_ESDB_COOKIE`
2. **Networking**: Ensure proper firewall rules for cluster communication
3. **Storage**: Use named volumes or bind mounts for data persistence
4. **Monitoring**: Implement external monitoring for cluster health
5. **Backups**: Regular backup of data volumes
6. **Resource Limits**: Set appropriate CPU and memory limits

### Hex Installation

ExESDB is also available as a Hex package for direct integration:

```elixir
def deps do
  [
    {:ex_esdb, "~> 0.0.18"}
  ]
end
```

## Contents

- [Getting Started](system/guides/getting_started.md)

## Releases

- [On Hex](https://hex.pm/packages/ex_esdb)
- [Release Documentation](https://hexdocs.pm/ex_esdb/index.html)
