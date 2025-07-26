# ExESDB Event Storming Session

## Overview

This document captures our event storming session to discover the reactive behaviors needed in our new event-driven ExESDB architecture. We'll explore key scenarios and identify:

- **Domain Events** (orange) - What happened in the system
- **Commands** (blue) - Actions triggered by events  
- **Actors/Systems** (yellow) - Who/what responds to events
- **Policies** (purple) - Rules that trigger reactions

## Scenario 1: System Startup & Initialization

### Timeline of Events:

1. **🟠 system_startup_initiated** 
   - **Actor**: ExESDB.System supervisor
   - **Data**: `{node: node(), timestamp: DateTime.t(), store_id: atom()}`

2. **🟠 control_system_ready**
   - **Actor**: ControlSystem 
   - **Triggered by**: PubSub + ControlPlane fully initialized
   - **Data**: `{pubsub_pid: pid(), control_plane_pid: pid()}`

3. **🟠 initialization_started**
   - **Actor**: ControlPlane
   - **Triggered by**: control_system_ready
   - **Data**: `{expected_systems: [atom()], node: node()}`

4. **🟠 subsystem_starting** (multiple in parallel)
   - **Actors**: PersistenceSystem, NotificationSystem, StoreSystem, ClusterSystem, GatewaySystem
   - **Triggered by**: initialization_started 
   - **Data**: `{system: atom(), node: node(), pid: pid()}`

5. **🟠 subsystem_ready** (multiple, asynchronous)
   - **Actors**: Each subsystem when fully initialized
   - **Data**: `{system: atom(), node: node(), services: [atom()]}`

6. **🟠 system_ready**
   - **Actor**: ControlPlane
   - **Triggered by**: All expected subsystem_ready events received
   - **Data**: `{ready_systems: [atom()], node: node(), ready_at: DateTime.t()}`

### Questions for Discussion:

1. **Should PersistenceSystem wait for anything before starting?** Or start immediately and handle dependencies reactively?

2. **What should NotificationSystem do when it receives `system_ready`?** Start accepting external subscriptions?

3. **Should GatewaySystem refuse connections until `system_ready`?** Or queue them?

---

## Scenario 2: Node Discovery & Cluster Formation

### Timeline of Events:

1. **🟠 node_discovered**
   - **Actor**: ClusterSystem (via LibCluster)
   - **Data**: `{discovered_node: node(), cluster_nodes: [node()], topology: atom()}`

2. **🟠 node_joining_cluster** 
   - **Actor**: ClusterSystem
   - **Data**: `{joining_node: node(), existing_nodes: [node()]}`

3. **🟠 store_coordinator_node_added**
   - **Actor**: StoreCoordinator (Khepri-based)
   - **Triggered by**: node_joining_cluster
   - **Data**: `{new_node: node(), khepri_cluster: [node()], coordinator_state: map()}`

4. **🟠 khepri_leader_changed**
   - **Actor**: StoreCoordinator (from Khepri leadership)
   - **Data**: `{old_leader: node() | nil, new_leader: node(), term: integer(), cluster_members: [node()]}`

5. **🟠 leader_responsibilities_assumed**
   - **Actor**: LeaderTracker
   - **Triggered by**: khepri_leader_changed (if this node is new leader)
   - **Data**: `{leader_node: node(), subscriptions_to_load: [map()]}`

6. **🟠 emitter_pools_starting**
   - **Actor**: NotificationSystem/EmitterSystem
   - **Triggered by**: leader_responsibilities_assumed
   - **Data**: `{subscription_count: integer(), pools_to_start: [String.t()]}`

### Key Architecture Points:

- **No data syncing**: Each node maintains its own persistent streams
- **StoreCoordinator prevents split-brain**: Uses Khepri consensus for cluster membership
- **LeaderTracker reads subscriptions**: When elected leader, reads all subscriptions from Khepri
- **EmitterPools follow leadership**: Only the leader runs emitter pools for subscriptions

### Questions for Discussion:

1. **How quickly should LeaderTracker respond to khepri_leader_changed?** Immediate or with some delay?

2. **What happens to in-flight subscription notifications during leadership change?** Drop them or buffer?

3. **Should non-leaders stop their emitter pools immediately or gracefully drain?**

---

## Scenario 3: Event Stream Write & Replication

### Timeline of Events:

1. **🟠 stream_write_requested**
   - **Actor**: GatewaySystem (from client)
   - **Data**: `{stream_id: String.t(), events: [map()], expected_version: integer()}`

2. **🟠 write_command_validated**
   - **Actor**: StoreSystem
   - **Data**: `{stream_id: String.t(), events: [map()], write_id: String.t()}`

3. **🟠 persistence_write_started**
   - **Actor**: PersistenceSystem
   - **Data**: `{stream_id: String.t(), events: [map()], write_id: String.t()}`

4. **🟠 events_persisted**
   - **Actor**: PersistenceSystem
   - **Data**: `{stream_id: String.t(), new_version: integer(), event_ids: [String.t()]}`

5. **🟠 replication_required** (if cluster)
   - **Actor**: StoreSystem (if leader)
   - **Triggered by**: events_persisted
   - **Data**: `{stream_id: String.t(), events: [map()], target_nodes: [node()]}`

6. **🟠 events_replicated**
   - **Actor**: ClusterSystem (from followers)
   - **Data**: `{stream_id: String.t(), replicated_to: [node()], write_id: String.t()}`

7. **🟠 write_acknowledged** 
   - **Actor**: StoreSystem
   - **Triggered by**: events_persisted + sufficient replication
   - **Data**: `{stream_id: String.t(), new_version: integer(), write_id: String.t()}`

8. **🟠 notification_triggered**
   - **Actor**: NotificationSystem
   - **Triggered by**: write_acknowledged
   - **Data**: `{stream_id: String.t(), events: [map()], subscribers: [pid()]}`

### Questions for Discussion:

1. **Should writes be rejected if cluster is in split-brain?** How do we detect this?

2. **What's the replication policy?** All nodes? Majority? Configurable?

3. **How should subscription notifications be ordered across the cluster?**

---

## Scenario 4: Node Failure & Recovery

### Timeline of Events:

1. **🟠 node_failure_detected**
   - **Actor**: ClusterSystem (via :net_kernel monitoring)
   - **Data**: `{failed_node: node(), detection_time: DateTime.t(), remaining_nodes: [node()]}`

2. **🟠 cluster_membership_changed**
   - **Actor**: ClusterSystem
   - **Data**: `{action: :leave, node: node(), new_membership: [node()]}`

3. **🟠 leadership_election_started** (if leader failed)
   - **Actor**: NotificationSystem/LeaderSystem
   - **Data**: `{reason: :leader_failure, candidates: [node()]}`

4. **🟠 subscription_orphaned** 
   - **Actor**: NotificationSystem
   - **Triggered by**: node_failure_detected
   - **Data**: `{orphaned_subscriptions: [String.t()], failed_node: node()}`

5. **🟠 failover_initiated**
   - **Actor**: StoreSystem (new leader)
   - **Data**: `{failed_node: node(), affected_streams: [String.t()]}`

6. **🟠 node_recovered**
   - **Actor**: ClusterSystem
   - **Data**: `{recovered_node: node(), recovery_time: DateTime.t()}`

7. **🟠 synchronization_required**
   - **Actor**: PersistenceSystem
   - **Triggered by**: node_recovered  
   - **Data**: `{recovering_node: node(), sync_from_version: integer()}`

### Questions for Discussion:

1. **How long should we wait before declaring a node failed?** 

2. **Should in-flight writes be retried automatically?** Or return error to client?

3. **How do we handle subscriptions that were on the failed node?** Auto-migrate? Client reconnect?

---

## Scenario 5: Subscription Management

### Timeline of Events:

1. **🟠 subscription_requested**
   - **Actor**: GatewaySystem (from client) 
   - **Data**: `{stream_pattern: String.t(), subscriber_pid: pid(), from_version: integer()}`

2. **🟠 subscription_validated**
   - **Actor**: StoreSystem
   - **Data**: `{subscription_id: String.t(), stream_pattern: String.t(), valid: boolean()}`

3. **🟠 subscription_registered**
   - **Actor**: NotificationSystem
   - **Data**: `{subscription_id: String.t(), subscriber_pid: pid(), stream_pattern: String.t()}`

4. **🟠 historical_events_requested**
   - **Actor**: NotificationSystem
   - **Triggered by**: subscription_registered (if from_version > 0)
   - **Data**: `{subscription_id: String.t(), from_version: integer(), stream_pattern: String.t()}`

5. **🟠 historical_events_loaded**
   - **Actor**: PersistenceSystem
   - **Data**: `{subscription_id: String.t(), events: [map()], has_more: boolean()}`

6. **🟠 subscription_active**
   - **Actor**: NotificationSystem  
   - **Triggered by**: historical_events_loaded (or immediately if from current)
   - **Data**: `{subscription_id: String.t(), subscriber_pid: pid()}`

### Questions for Discussion:

1. **Should subscriptions be cluster-wide or node-local?**

2. **How do we handle subscription failover when a node crashes?**

3. **Should we batch historical events or stream them individually?**

---

## Reactive Policies to Define

Based on these scenarios, we need to define several reactive policies:

### **System Coordination Policies**
- 🟣 **When** `subsystem_starting` **→** Update system status, continue parallel startup
- 🟣 **When** `subsystem_ready` **→** Check if all systems ready, possibly publish `system_ready`
- 🟣 **When** `system_ready` **→** Enable external API, start accepting connections

### **Cluster Management Policies**  
- 🟣 **When** `node_discovered` **→** Initiate connection, exchange metadata
- 🟣 **When** `cluster_membership_changed` + `action: :join` **→** Trigger leader election if needed
- 🟣 **When** `leader_elected` **→** Synchronize state if follower, begin leadership duties if leader

### **Write & Replication Policies**
- 🟣 **When** `events_persisted` + `cluster_mode` **→** Initiate replication to followers  
- 🟣 **When** `replication_completed` **→** Acknowledge write to client
- 🟣 **When** `write_acknowledged` **→** Trigger subscription notifications

### **Failure & Recovery Policies**
- 🟣 **When** `node_failure_detected` **→** Update cluster membership, check for leader election
- 🟣 **When** `leader_failed` **→** Start leader election among remaining nodes
- 🟣 **When** `node_recovered` **→** Sync missing data, restore subscriptions

---

## Next Steps for Implementation

1. **Create event schemas** for each identified event type
2. **Implement direct event publishing** in each subsystem for their lifecycle events
3. **Define event routing rules** - which systems subscribe to which event types via LoggerWorkers
4. **Create integration tests** for each scenario end-to-end
5. **Implement reactive behaviors** in specific components that need them

## Questions for Further Discussion

1. **Event ordering guarantees** - Do we need ordered delivery within event categories?
2. **Event persistence** - Should control plane events be persisted for replay?
3. **Backpressure handling** - What happens if event processing falls behind?
4. **Event versioning** - How do we handle schema evolution of control events?
5. **Monitoring & observability** - What metrics should we track for event flows?

---

*This is a living document - we'll continue to refine these scenarios and discover new events as we implement the reactive behaviors.*
