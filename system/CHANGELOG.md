# Changelog

## version 0.1.1 (2025.07.13)

### StoreRegistry Refactoring

#### Enhanced Architecture

- **Store Registration Centralization**: Moved store registration functionality from `StoreCluster` to dedicated `StoreRegistry` module
- **Self-Registration**: `StoreRegistry` now automatically registers its own store during initialization when `store_id` is provided
- **Simplified StoreCluster**: `StoreCluster` now focuses purely on cluster coordination without store registration concerns

#### API Integration

- **ExESDBGater.API Integration**: `list_stores()` function now directly calls `ExESDB.StoreRegistry.list_stores()` instead of maintaining local state
- **Single Source of Truth**: Store information is now centralized in `StoreRegistry` across the entire system
- **Improved Error Handling**: Added proper error handling for StoreRegistry calls in GaterAPI

#### System Integration

- **StoreSystem Supervision**: Added `StoreRegistry` to the `StoreSystem` supervisor with proper startup order
- **Component Isolation**: Each component now has a single, well-defined responsibility
- **Cleaner State Management**: Removed redundant store state from multiple components

#### Benefits

- **Separation of Concerns**: Clear boundaries between clustering and registration responsibilities
- **Maintainability**: Easier to maintain and reason about store registration logic
- **Testability**: Store registration can now be tested in isolation
- **Reduced Coupling**: Components are less tightly coupled and more modular

## version 0.0.17 (2025.07.01)

### Auto-Clustering

- `ExESDB` nodes now automatically join the cluster
- "Split-Brain" scenarios are now mitigated

### BCUtils

- All functionality related to styling is now transferred to the `:bc_utils` package.
- Added a Banner after startup.
- Logger filtering for Swarm and LibCluster noise reduction (via BCUtils.LoggerFilters)

### ExESDB Logger Filtering

#### Features

The `ExESDB.LoggerFilters` module provides additional log noise reduction specifically for ExESDB's distributed systems components:

- **Ra Consensus Filtering**: Reduces Ra heartbeat, append_entries, pre_vote, request_vote, and routine state transition messages while preserving all errors/warnings
- **Khepri Database Filtering**: Filters internal Khepri operations (cluster state, store operations) at info/debug levels while maintaining error/warning visibility
- **Enhanced Swarm Filtering**: Complements BCUtils filtering with additional ExESDB-specific Swarm noise reduction
- **Enhanced LibCluster Filtering**: Complements BCUtils filtering with additional ExESDB-specific cluster formation noise reduction

#### Benefits

- Dramatically improves log readability in development and production environments
- Intelligent filtering preserves all error and warning messages
- Focused on ExESDB-specific distributed systems infrastructure (Ra, Khepri)
- Works in conjunction with BCUtils.LoggerFilters for comprehensive noise reduction

### ExESDBGater

- The `ExESDB.GatewayAPI` is moved to the `:ex_esdb_gater` package.

#### Features

Snapshots Subsystem provides cluster wide support for reading and writing snapshots, using a key derived from the `source_uuid`, `stream_uuid` and `version` of the snapshot.

## version 0.0.16 (2025.06.26)

### Snapshots

#### Features

Snapshots Subsystem provides cluster wide support for reading and writing snapshots, using a key derived from the `source_uuid`, `stream_uuid` and `version` of the snapshot.

- `record_snapshot/5` function
- `delete_snapshot/4` function
- `read_snapshot/4` function
- `list_snapshots/3` function

#### Supported by Gateway API

It is advised to use `ExESDB.GatewayAPI` to access the Snapshots Subsystem.

## version 0.0.15 (2025.06.15)

### Subscriptions

#### Transient subscriptions

- `:by_stream`, `:by_event_type`, `:by_event_pattern`, `:by_event_payload`
- Events are forwarded to `Phoenix.PubSub` for now

#### Persistent subscriptions

- `:by_stream`, with support for replaying from a given version
- Events are forwarded to a specific subscriber process
- `ack_event/3` function is provided

#### "Follow-the-Leader"

Emitter processes are automatically started on the leader node,
when a new leader is elected.

#### Gateway API

- A cluster-wide gateway API is provided
- is an entry point for all the other modules
- provides basic High-Availability and Load-Balancing

## version 0.0.9-alpha (2025.05.04)

### Subscriptions

- `ExESDB.Subscriptions` module
- `func_registrations.exs` file
- emitter trigger in `khepri` now only uses the `erlang`-native :pg library (process groups)

#### Skeleton support for Commanded

- `ExESDB.Commanded.Adapter` module
- `ExESDB.Commanded.Mapper` module

## version 0.0.8-alpha

### 2025.04.13

- Added `ExESDB.EventStore.stream_forward/4` function
- Added `BeamCampus.ColorFuncs` module
- Added `ExESDB.Commanded.Adapter` module
- Refactored `ExESDB.EventStreamReader` and `ExESDB.EventStreamWriter` modules:
- Streams are now read and written using the `ExESDB.Streams` module
- Removed `ExESDB.EventStreamReader` module
- Removed `ExESDB.EventStreamWriter` module

## version 0.0.7-alpha

## version 0.0.1-alpha

### 2025.03.25

- Initial release
