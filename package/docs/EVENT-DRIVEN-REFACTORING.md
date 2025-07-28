# ExESDB Event-Driven Architecture Refactoring

## Overview

This document describes the comprehensive refactoring of ExESDB from a sequential, cluster/single-mode architecture to a fully reactive, event-driven system. This transformation eliminates startup race conditions and provides better fault tolerance through reactive coordination.

## Architecture Transformation

### **Before: Sequential Architecture**
```
SINGLE NODE MODE:
1. CoreSystem: Critical infrastructure (PersistenceSystem + NotificationSystem + StoreSystem)
2. GatewaySystem: External interface with pooled workers

CLUSTER MODE:
1. CoreSystem: Critical infrastructure (PersistenceSystem + NotificationSystem + StoreSystem)
2. LibCluster: Node discovery and connection (after core is ready)
3. ClusterSystem: Cluster coordination and membership
4. GatewaySystem: External interface (LAST - only after clustering is ready)
```

### **After: Reactive Architecture**
```
UNIFIED REACTIVE MODE:
1. ControlSystem: Event coordination infrastructure (PubSub + ControlPlane)
2. All other systems start in parallel and report readiness via events:
   - PersistenceSystem
   - NotificationSystem  
   - StoreSystem
   - ClusterSystem (handles node discovery)
   - GatewaySystem
3. Systems report readiness to ControlPlane via events
4. ControlPlane coordinates system-wide readiness
```

## Key Design Principles

### **Reactive Design Principles:**

- **No cluster/single distinction**: All systems start uniformly and adapt based on discovery
- **Parallel startup**: Systems start independently and report readiness asynchronously  
- **Event-driven coordination**: Control Plane orchestrates via pub/sub events
- **Self-organizing**: Nodes discover each other and emit cluster events

### **System Lifecycle:**

1. **ControlSystem** starts first (PubSub + ControlPlane)
2. All other systems start in **parallel**
3. Systems report readiness to ControlPlane via events
4. ControlPlane coordinates system-wide readiness

### **Node Discovery & Clustering:**

- ClusterSystem always starts (handles both single and cluster modes)
- LibCluster integration for automatic node discovery
- Nodes emit events when joining/leaving cluster
- Other systems react to cluster membership changes

## Implementation Details

### **Main System Supervisor (`ExESDB.System`)**

```elixir
children = [
  # ControlSystem MUST start first - provides event coordination infrastructure
  {ExESDB.ControlSystem, opts},
  
  # All other systems start in parallel and report readiness via events
  {ExESDB.PersistenceSystem, opts},
  {ExESDB.NotificationSystem, opts}, 
  {ExESDB.StoreSystem, opts},
  {ExESDB.ClusterSystem, opts},
  {ExESDB.GatewaySystem, opts}
]
|> maybe_add_libcluster(libcluster_child)

# Changed to :one_for_one for better fault isolation
Supervisor.init(children, strategy: :one_for_one)
```

### **Control Plane Event Handling**

The ControlPlane now handles system readiness reactively:

```elixir
def handle_info({:control_plane_event, %{event_type: :subsystem_ready, data: %{system: system_name}}}, state) do
  # Add system to ready systems
  new_ready_systems = MapSet.put(state.ready_systems, system_name)
  new_managed_systems = Map.put(state.managed_systems, system_name, :ready)
  
  updated_state = %{state | 
    ready_systems: new_ready_systems,
    managed_systems: new_managed_systems
  }
  
  # Check if all expected systems are ready
  final_state = check_system_readiness(updated_state)
  {:noreply, final_state}
end
```

### **Reactive Readiness Checking**

```elixir
defp check_system_readiness(state) do
  expected_set = MapSet.new(state.expected_systems)
  
  if MapSet.equal?(state.ready_systems, expected_set) do
    Logger.info("ControlPlane: All expected systems are ready!")
    
    # Publish system ready event
    publish(state.store_id, :system, :system_ready, %{
      ready_systems: MapSet.to_list(state.ready_systems),
      node: node()
    })
    
    %{state | system_status: :ready}
  else
    missing_systems = MapSet.difference(expected_set, state.ready_systems)
    Logger.debug("ControlPlane: Still waiting for systems: #{inspect(MapSet.to_list(missing_systems))}")
    state
  end
end
```

## Event Types and Flow

### **System Lifecycle Events**

- `:initialization_started` - Published by ControlPlane when system starts
- `:subsystem_starting` - Published by individual systems when they begin startup
- `:subsystem_ready` - Published by systems when fully initialized
- `:subsystem_failed` - Published by systems on startup failure
- `:system_ready` - Published by ControlPlane when all expected systems are ready

### **Cluster Events**

- `:node_joined` - When a node joins the cluster
- `:node_left` - When a node leaves the cluster
- `:cluster_formed` - When initial cluster is established
- `:leader_elected` - When cluster leadership changes

### **Event Flow Example**

```
1. ControlSystem starts (PubSub + ControlPlane)
2. ControlPlane publishes :initialization_started
3. All subsystems start in parallel
4. Each subsystem publishes :subsystem_starting
5. Each subsystem completes initialization
6. Each subsystem publishes :subsystem_ready
7. ControlPlane receives all :subsystem_ready events
8. ControlPlane publishes :system_ready
9. ClusterSystem discovers nodes and publishes :node_joined events
10. Other systems react to cluster membership changes
```

## Benefits of Reactive Architecture

### **Performance Benefits:**

- **Faster Startup**: Parallel system initialization eliminates blocking dependencies
- **Reduced Latency**: No waiting for sequential system startup
- **Better Resource Utilization**: Systems can initialize concurrently

### **Reliability Benefits:**

- **Better Fault Tolerance**: Event-driven coordination is more resilient to failures
- **Fault Isolation**: `:one_for_one` supervision strategy isolates component failures
- **Graceful Degradation**: Systems can handle missing dependencies reactively

### **Maintainability Benefits:**

- **Simplified Logic**: No complex branching based on cluster modes
- **Better Observability**: All system lifecycle events are published and trackable
- **Decoupled Components**: Systems communicate only via events
- **Easier Testing**: Event-driven behavior is more predictable and testable

### **Operational Benefits:**

- **Reactive Design**: Systems adapt dynamically to cluster changes
- **Self-Organizing**: Automatic node discovery and cluster formation
- **Better Monitoring**: Rich event stream for system observability
- **Uniform Behavior**: Single deployment mode handles all scenarios

## Migration Path

### **Removed Components:**
- Sequential startup logic in ControlPlane
- Cluster/single mode branching in System supervisor
- Complex dependency management between systems

### **Added Components:**
- Reactive readiness tracking in ControlPlane
- Event-driven system coordination
- Parallel system startup logic
- Self-organizing cluster behavior

### **Modified Components:**
- **ExESDB.System**: Now starts all systems in parallel after ControlSystem
- **ExESDB.ControlPlane**: Purely reactive - waits for system readiness events
- **Expected Systems**: Updated to include cluster system in all modes

## Event-Driven Coordination Pattern

This refactoring implements a comprehensive event-driven coordination pattern where:

1. **No Direct Dependencies**: Systems don't directly depend on each other
2. **Event-Based Communication**: All coordination happens via published events
3. **Reactive State Management**: Systems react to events rather than managing state directly
4. **Asynchronous Startup**: All systems start in parallel and report readiness
5. **Dynamic Adaptation**: Systems adapt to changing cluster membership via events

## Future Enhancements

The reactive architecture enables several future enhancements:

- **Dynamic System Addition**: New systems can be added at runtime
- **Health Monitoring**: Continuous health checking via events
- **Load Balancing**: Dynamic load balancing based on system events
- **Auto-scaling**: Automatic scaling based on system metrics
- **Circuit Breakers**: Event-driven circuit breaker patterns
- **Distributed Tracing**: Event correlation for distributed tracing

## Conclusion

This refactoring transforms ExESDB from a complex, sequential system with race conditions into a clean, reactive architecture that eliminates startup dependencies and provides better fault tolerance. The event-driven design makes the system more maintainable, observable, and resilient while improving startup performance through parallel initialization.

The reactive pattern provides a solid foundation for future enhancements and makes ExESDB more suitable for distributed, cloud-native deployments where systems need to adapt dynamically to changing conditions.
