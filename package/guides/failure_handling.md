# Failure Handling in ExESDB

This guide provides a comprehensive overview of all failure handling strategies implemented in ExESDB, from individual process failures to cluster-wide outages. ExESDB is built on the BEAM's "let it crash" philosophy while providing robust recovery mechanisms at every level.

## Table of Contents

1. [Failure Categories](#failure-categories)
2. [Supervision Strategies](#supervision-strategies)
3. [Node-Level Failures](#node-level-failures)
4. [Network Partitions](#network-partitions)
5. [Data Consistency](#data-consistency)
6. [Worker Process Failures](#worker-process-failures)
7. [Storage Failures](#storage-failures)
8. [Configuration and Monitoring](#configuration-and-monitoring)
9. [Recovery Procedures](#recovery-procedures)
10. [Testing Failure Scenarios](#testing-failure-scenarios)

## Failure Categories

ExESDB handles failures across multiple dimensions:

### 1. Process-Level Failures
- **Worker crashes**: Individual GenServer processes failing
- **Supervisor crashes**: Supervisor trees failing
- **Application crashes**: Entire OTP applications going down

### 2. Node-Level Failures
- **Hard crashes**: Sudden node termination (power loss, kill -9)
- **Soft crashes**: Graceful shutdowns and restarts
- **Network isolation**: Node becomes unreachable but continues running

### 3. Cluster-Level Failures
- **Split-brain scenarios**: Network partitions causing multiple leaders
- **Quorum loss**: Insufficient nodes for consensus
- **Data corruption**: Storage-level integrity issues

### 4. Storage-Level Failures
- **Disk failures**: Storage becoming unavailable
- **Corruption**: Data integrity violations
- **Performance degradation**: Slow storage affecting operations

## Supervision Strategies

ExESDB uses a hierarchical supervision tree with different restart strategies for different components:

### Root Supervision Tree

```
ExESDB.App (one_for_one)
└── ExESDB.System (one_for_one)
    ├── Phoenix.PubSub
    ├── Cluster.Supervisor (LibCluster)
    ├── PartitionSupervisor (EmitterPools)
    ├── ExESDB.Store
    ├── ExESDB.ClusterSystem (one_for_one)
    ├── ExESDB.Streams (one_for_one)
    ├── ExESDB.Snapshots
    ├── ExESDB.Subscriptions (one_for_one)
    ├── ExESDB.GatewaySupervisor (one_for_one)
    └── ExESDB.LeaderSystem (one_for_one)
```

### Restart Strategies by Component

| Component | Strategy | Restart | Reason |
|-----------|----------|---------|--------|
| **System** | `:one_for_one` | `:permanent` | Core system components |
| **ClusterSystem** | `:one_for_one` | `:permanent` | Independent cluster services |
| **Streams** | `:one_for_one` | `:permanent` | Stream readers/writers are independent |
| **GatewaySupervisor** | `:one_for_one` | `:permanent` | Gateway API and workers |
| **StreamsWriterWorker** | `:temporary` | `:temporary` | TTL-based lifecycle |
| **StreamsReaderWorker** | `:temporary` | `:temporary` | On-demand workers |
| **GatewayWorker** | `:permanent` | `:permanent` | Core gateway functionality |

### Worker Lifecycle Management

**Stream Workers**:
- Use `:temporary` restart to prevent infinite restart loops
- Implement TTL-based shutdown for resource management
- Automatically clean up Swarm registrations on exit

**Gateway Workers**:
- Use `:permanent` restart for high availability
- Register with Swarm for distributed load balancing
- Handle graceful shutdown with cleanup

## Node-Level Failures

### Hard Crash Detection and Recovery

When a node crashes unexpectedly, multiple systems work together to detect and recover:

#### 1. NodeMonitor Service (Fast Detection)

**Problem**: Traditional Raft consensus timeouts can take 10-30 seconds
**Solution**: Proactive health monitoring with 6-second detection

This solution implements a comprehensive approach to quickly detect and handle node failures:

### 1. NodeMonitor Service

**Location**: `lib/ex_esdb/node_monitor.ex`

**Features**:
- **Active Health Probing**: Probes cluster nodes every 2 seconds
- **Multi-Layer Health Checks**: Verifies node connectivity + application health
- **Fast Failure Detection**: Marks nodes as failed after 3 consecutive probe failures (6 seconds total)
- **Automatic Cleanup**: Removes stale Swarm registrations from failed nodes
- **Event-Driven Updates**: Responds to `:nodeup`/`:nodedown` events

**Configuration**:
```elixir
# Default settings (configurable)
probe_interval: 2_000,     # 2 seconds between probes
failure_threshold: 3,      # 3 failures = node considered down
probe_timeout: 1_000       # 1 second timeout per probe
```

### 2. Integration with Existing Architecture

The NodeMonitor integrates seamlessly with your current LibCluster setup:

**Modified Files**:
- `lib/ex_esdb/cluster_system.ex` - Added NodeMonitor to supervision tree
- Uses existing `ClusterCoordinator` for split-brain prevention
- Leverages current `Swarm` registrations for worker cleanup

### 3. How It Works

#### Health Probe Cycle (Every 2 seconds):
1. **Discover Nodes**: Get cluster members from Khepri
2. **Probe Health**: Test each node with RPC calls
3. **Track Failures**: Increment failure count for unresponsive nodes
4. **Trigger Cleanup**: Handle nodes that exceed failure threshold
5. **Update State**: Maintain monitoring state for next cycle

#### Failure Detection:
```elixir
# Multi-layer health check
1. Node connectivity: :rpc.call(node, :erlang, :node, [])
2. Application health: Check if :ex_esdb is running
3. Failure tracking: 3 consecutive failures = node down
```

#### Automatic Cleanup:
```elixir
# When a node is detected as failed:
1. Remove Swarm worker registrations from failed node
2. Update cluster state (notify other components)
3. Clean up subscriptions tied to failed node
4. Log failure for monitoring/alerting
```

### 4. Benefits

**Fast Detection**: 
- Traditional Raft consensus timeout: 10-30 seconds
- This solution: 6 seconds (3 failures × 2 second intervals)

**Proactive Cleanup**:
- Prevents requests to unavailable workers
- Maintains cluster integrity
- Enables faster recovery

**Graceful Degradation**:
- System continues operating with remaining nodes
- Workers redistribute automatically via Swarm
- No single point of failure

### 5. Usage

#### Check Cluster Health:
```elixir
# Get current health status
ExESDB.NodeMonitor.health_status()
# Returns: %{
#   monitored_nodes: [:node1@host, :node2@host],
#   node_failures: %{},
#   last_seen: %{:node1@host => 1625567890123},
#   threshold: 3
# }
```

#### Manual Node Probe:
```elixir
# Force probe a specific node
ExESDB.NodeMonitor.probe_node(:node1@host)
# Returns: :healthy or :unhealthy
```

### 6. Configuration Options

**Environment Variables** (can be added to your config):
```elixir
config :ex_esdb, :node_monitor,
  probe_interval: 2_000,      # How often to probe (ms)
  failure_threshold: 3,       # Failures before marking as down
  probe_timeout: 1_000,       # Timeout per probe (ms)
  cleanup_stale_workers: true # Auto-cleanup Swarm registrations
```

### 7. Monitoring and Observability

**Log Messages**:
- `NodeMonitor started with 2000ms intervals`
- `Health probe failed for node1@host (2/3)`
- `Node node1@host detected as failed, initiating cleanup`
- `Cleaning up Swarm registration: {:gateway_worker, node1@host, 1234}`

**Integration Points**:
- Logs can be forwarded to your monitoring system
- Health status can be exposed via HTTP endpoints
- Alerts can be triggered on node failures

### 8. Advanced Features (Future Extensions)

The solution is designed to be extensible:

**Planned Enhancements**:
- **Forced Khepri Node Removal**: Actively remove failed nodes from consensus
- **Worker Redistribution**: Trigger immediate rebalancing of Swarm workers
- **Leader Election**: Handle leader failures more aggressively
- **Custom Health Checks**: Application-specific health validation

### 9. Deployment

**No Breaking Changes**: 
- Fully backward compatible with existing cluster
- Can be deployed incrementally (node by node)
- Falls back gracefully if monitoring fails

**Resource Usage**:
- Minimal CPU overhead (RPC calls every 2 seconds)
- Low memory footprint (tracks failure state only)
- Network traffic: ~1KB per node per probe

### 10. Testing the Solution

**Chaos Engineering**:
```bash
# Simulate hard crash
docker kill ex-esdb-node1

# Monitor logs for detection
docker logs ex-esdb-node2 | grep NodeMonitor

# Verify cleanup
# Should see Swarm registrations removed within 6 seconds
```

**Expected Timeline**:
- T+0: Node crashes
- T+2s: First probe failure detected
- T+4s: Second probe failure  
- T+6s: Third probe failure, node marked as failed
- T+6s: Cleanup initiated (Swarm registrations removed)
- T+8s: Next probe cycle (failed node no longer monitored)

#### 2. LibCluster Integration

**Built-in Node Detection**:
- Uses `:net_kernel.monitor_nodes(true, [:nodedown_reason])` for immediate notification
- Gossip-based discovery helps detect network issues
- Automatic cluster formation and healing

#### 3. ClusterCoordinator

**Split-Brain Prevention**:
- Deterministic leader election (lowest node name)
- Prevents multiple clusters from forming
- Coordinates safe cluster joining

**Features**:
```elixir
# Prevent split-brain during network partitions
def should_be_cluster_coordinator(connected_nodes) do
  all_nodes = [node() | connected_nodes] |> Enum.sort()
  node() == List.first(all_nodes)
end
```

### Graceful Shutdown Handling

ExESDB handles graceful shutdowns through multiple mechanisms:

**Signal Handling**:
```elixir
# SIGTERM and SIGQUIT handling
:os.set_signal(:sigterm, :handle)
:os.set_signal(:sigquit, :handle)
```

**Process Cleanup**:
- Workers unregister from Swarm before termination
- Subscription state is persisted
- Transactions are completed or rolled back

## Network Partitions

### Split-Brain Prevention

ExESDB implements multiple layers to prevent split-brain scenarios:

#### 1. ClusterCoordinator Logic
- **Deterministic Election**: Uses sorted node names for consistent leader selection
- **Existing Cluster Detection**: Searches for active clusters before forming new ones
- **Coordinated Joining**: Prevents multiple simultaneous cluster formations

#### 2. Raft Consensus (Ra/Khepri)
- **Majority Quorum**: Requires majority of nodes for write operations
- **Leader Election**: Automatic failover when leader becomes unavailable
- **Log Replication**: Ensures consistency across cluster members

#### 3. Partition Tolerance
**Minority Partition Behavior**:
- Nodes in minority partition become read-only
- No new events can be written without quorum
- Automatic healing when partition resolves

**Majority Partition Behavior**:
- Continues normal operations
- Elects new leader if needed
- Accepts new writes and maintains consistency

### Network Partition Recovery

**Automatic Healing Process**:
1. **Detection**: Nodes detect network connectivity restoration
2. **State Synchronization**: Minority nodes sync with majority
3. **Conflict Resolution**: Raft log reconciliation
4. **Service Restoration**: Workers redistribute across all nodes

## Data Consistency

### Transaction Handling

ExESDB provides ACID guarantees through Khepri transactions:

**Optimistic Concurrency Control**:
```elixir
def try_append_events(store, stream_id, expected_version, events) do
  current_version = get_current_version(store, stream_id)
  
  if current_version == expected_version do
    # Proceed with append
    append_events_atomically(store, stream_id, events, current_version)
  else
    {:error, :wrong_expected_version}
  end
end
```

**Transaction Isolation**:
- Uses Khepri's MVCC for concurrent access
- Transactions are atomic and isolated
- Automatic rollback on failures

### Conflict Resolution

**Version Conflicts**:
- Expected version mismatches return `:wrong_expected_version`
- Clients must retry with updated expected version
- No automatic conflict resolution (explicit client handling)

**Concurrent Writes**:
- Only one writer per stream at a time
- Serialized access through stream-specific workers
- Queue management for high-throughput scenarios

## Worker Process Failures

### Stream Worker Failure Handling

#### Writers (StreamsWriterWorker)
**Lifecycle Management**:
- `:temporary` restart strategy prevents restart loops
- TTL-based shutdown for resource management
- Automatic Swarm cleanup on termination

**Failure Scenarios**:
```elixir
# TTL-based shutdown
def handle_info(:check_idle, %{idle_since: idle_since} = state) do
  writer_ttl = Options.writer_idle_ms()
  
  if idle_since + writer_ttl < epoch_time_ms() do
    Process.exit(self(), :ttl_reached)
  end
  
  {:noreply, state}
end

# Graceful cleanup on exit
def handle_info({:EXIT, _pid, reason}, %{worker_name: name} = state) do
  Swarm.unregister_name(name)
  {:noreply, state}
end
```

#### Readers (StreamsReaderWorker)
- Similar TTL-based lifecycle
- On-demand creation for read operations
- Automatic cleanup when no longer needed

### Gateway Worker Failures

**High Availability Design**:
- `:permanent` restart strategy for critical gateway functions
- Load balancing through random worker selection
- Graceful failover to other gateway workers

**Worker Distribution**:
```elixir
# Random load balancing with fallback
defp random_gateway_worker do
  case Swarm.members(:gateway_workers) do
    [] -> 
      # Fallback to local gateway if no distributed workers
      ExESDB.GatewayWorker
    workers -> 
      workers |> Enum.random() |> elem(1)
  end
end
```

### Subscription Worker Failures

**"Follow-the-Leader" Pattern**:
- Subscription workers automatically migrate to leader node
- Persistent subscription state survives worker failures
- Automatic restart and state recovery

## Storage Failures

### Khepri/Ra Storage Resilience

**Data Directory Management**:
```elixir
# Configurable data directory
config :ex_esdb, :khepri,
  data_dir: "/data",
  store_id: :reg_gh,
  timeout: 2_000
```

**Failure Scenarios**:

#### Disk Space Exhaustion
- **Detection**: Monitor disk usage in production
- **Mitigation**: Implement log compaction and cleanup
- **Recovery**: Restore from snapshots if available

#### Corruption Detection
- **Checksums**: Ra maintains data integrity checks
- **Verification**: Periodic consistency checks
- **Recovery**: Restore from cluster peers or backups

#### Performance Degradation
- **Monitoring**: Track operation latencies
- **Alerting**: Set thresholds for response times
- **Mitigation**: Scale storage or redistribute load

### Backup and Recovery

**Snapshot Management**:
- Regular snapshots of aggregate state
- Version-based snapshot storage
- Distributed snapshot replication

**Disaster Recovery**:
1. **Data Loss Prevention**: Multi-node replication
2. **Point-in-Time Recovery**: Event replay from snapshots
3. **Cross-Region Backup**: External backup strategies

## Configuration and Monitoring

### Health Check Endpoints

**Cluster Health**:
```elixir
# Check overall cluster status
ExESDB.NodeMonitor.health_status()

# Check specific node
ExESDB.NodeMonitor.probe_node(:node1@host)

# Get cluster members
ExESDB.Cluster.members(store_id)
```

**Performance Metrics**:
- Operation latencies
- Throughput measurements
- Resource utilization
- Error rates

### Logging and Alerting

**Structured Logging**:
```elixir
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:mfa]
```

**Alert Categories**:
- **Critical**: Node failures, data corruption
- **Warning**: Performance degradation, high error rates
- **Info**: Normal operations, state changes

### Configuration Best Practices

**Production Settings**:
```elixir
# Timeouts
config :ex_esdb, :khepri,
  timeout: 5_000  # Increase for production

# Node monitoring
config :ex_esdb, :node_monitor,
  probe_interval: 2_000,
  failure_threshold: 3,
  probe_timeout: 1_000

# Worker TTL
config :ex_esdb, :worker_idle_ms, 300_000  # 5 minutes
```

**Development Settings**:
```elixir
# Faster timeouts for development
config :ex_esdb, :khepri,
  timeout: 10_000

# Shorter TTL for resource management
config :ex_esdb, :worker_idle_ms, 60_000  # 1 minute
```

## Recovery Procedures

### Manual Recovery Steps

#### Single Node Recovery
1. **Identify Issue**: Check logs and monitoring
2. **Isolate Node**: Remove from load balancer if needed
3. **Restart Service**: Use graceful restart procedures
4. **Verify Health**: Confirm cluster membership
5. **Restore Traffic**: Gradually return to service

#### Cluster Recovery
1. **Assess Damage**: Determine scope of failure
2. **Quorum Check**: Ensure majority of nodes available
3. **Leader Election**: Verify or trigger new leader election
4. **Data Integrity**: Check for any corruption
5. **Service Validation**: Test critical operations

### Automated Recovery

**Self-Healing Mechanisms**:
- Automatic process restarts via supervision
- Worker redistribution through Swarm
- Cluster reformation after partitions
- Leader election on failures

**Monitoring Integration**:
- Health check failures trigger alerts
- Automatic scaling based on load
- Proactive maintenance scheduling

## Testing Failure Scenarios

### Chaos Engineering

**Node Failures**:
```bash
# Hard crash simulation
docker kill ex-esdb-node1

# Network partition simulation
iptables -A INPUT -s <node2_ip> -j DROP
iptables -A OUTPUT -d <node2_ip> -j DROP

# Resource exhaustion
stress --cpu 8 --io 4 --vm 2 --vm-bytes 128M --timeout 60s
```

**Service Failures**:
```bash
# Stop specific services
systemctl stop ex_esdb

# Simulate disk failures
fill-disk.sh /data 95%

# Network latency injection
tc qdisc add dev eth0 root netem delay 500ms
```

### Test Scenarios

#### Scenario 1: Single Node Failure
**Steps**:
1. Start 3-node cluster
2. Kill one node abruptly
3. Verify cluster continues operating
4. Check client request success rates
5. Restart failed node
6. Verify automatic rejoin

**Expected Results**:
- Cluster maintains quorum (2/3 nodes)
- No data loss
- Client operations continue
- Failed node rejoins automatically

#### Scenario 2: Network Partition
**Steps**:
1. Start 3-node cluster
2. Create network partition (2 vs 1 node)
3. Verify majority partition continues
4. Check minority partition becomes read-only
5. Heal partition
6. Verify automatic reconciliation

**Expected Results**:
- Majority partition elects new leader
- Minority partition rejects writes
- Healing triggers state synchronization
- No data inconsistencies

#### Scenario 3: Leader Failure
**Steps**:
1. Identify current leader
2. Kill leader node
3. Verify new leader election
4. Check subscription migration
5. Validate continued operations

**Expected Results**:
- New leader elected within timeout
- Subscriptions migrate to new leader
- Client operations resume
- Worker redistribution occurs

### Monitoring During Tests

**Key Metrics**:
- Response times
- Error rates
- Memory usage
- CPU utilization
- Network connectivity
- Disk I/O

**Log Analysis**:
```bash
# Monitor cluster events
docker logs -f ex-esdb-node1 | grep -E "(NodeMonitor|Cluster|Leader)"

# Check for errors
docker logs ex-esdb-node1 | grep -i error

# Monitor worker redistribution
docker logs ex-esdb-node1 | grep -i swarm
```

## Conclusion

ExESDB provides comprehensive failure handling across all system levels, from individual process failures to cluster-wide outages. The system is designed with the BEAM's "let it crash" philosophy while ensuring data consistency and high availability through:

**Key Strengths**:
- **Fast Failure Detection**: 6-second node failure detection vs 10-30 second consensus timeouts
- **Automatic Recovery**: Self-healing mechanisms at every level
- **Data Consistency**: ACID guarantees through Raft consensus
- **High Availability**: No single points of failure
- **Graceful Degradation**: System continues operating with reduced capacity

**Operational Benefits**:
- **Reduced Downtime**: Automatic failover and recovery
- **Operational Simplicity**: Minimal manual intervention required
- **Predictable Behavior**: Well-defined failure modes and recovery procedures
- **Monitoring Integration**: Comprehensive observability and alerting

**Production Readiness**:
- Battle-tested BEAM supervision principles
- Proven Raft consensus implementation (Ra)
- Comprehensive testing scenarios
- Clear operational procedures

This failure handling strategy ensures that ExESDB can operate reliably in production environments while maintaining the flexibility and resilience that makes BEAM-based systems ideal for distributed, fault-tolerant applications.
