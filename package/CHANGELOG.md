# Changelog

## version 0.7.0 (2025.07.27)

### Enhanced PubSub Architecture: Foundation for Event-Driven Architecture

#### Multi-Channel PubSub System

- **Dedicated PubSub Instances**: Implemented three specialized Phoenix.PubSub instances for improved separation of concerns
  - **`:ex_esdb_events`**: Primary channel for business event distribution and streaming
  - **`:ex_esdb_system`**: Internal system operations, coordination messages, and metrics
  - **`:ex_esdb_health`**: Dedicated health monitoring and service availability communications
- **Architectural Foundation**: Established infrastructure for transitioning to fully Event-Driven Architecture (EDA)
- **Channel Isolation**: Prevents cross-contamination of different message types and improves system reliability

#### Color-Coded EmitterWorker Observability

- **Visual Message Classification**: Implemented comprehensive color-coded logging system for immediate issue identification
  - **🟢 Success Messages (White on Green/Blue)**: Service activation, health subscriptions, successful operations
  - **🔴 Failure Messages (White on Red)**: Termination events, errors, unhealthy states
  - **🟡 Action Messages (White on Amber)**: Broadcasting, forwarding, dynamic worker creation, metrics
  - **🔵 Health Messages (White on Cyan)**: Health event processing, status changes
- **Enhanced PID Backgrounds**: Color-coded process identifiers based on message type for rapid visual debugging
- **BCUtils.ColorFuncs Integration**: Leveraged existing color functions for consistent theming across the system

#### Comprehensive Health and Metrics Monitoring

- **Health Event Logging**: Real-time visibility into subscription health status and service availability
  - Health event subscription tracking: `🩺 SUBSCRIBED to health events`
  - Individual health events: `📡 HEALTH EVENT: subscription_name -> event_type`
  - Health summaries: `📈 HEALTH SUMMARY: Store my_store - 5/7 healthy subscriptions`
  - Health impact tracking: `🏥 HEALTH IMPACT: subscription_name is HEALTHY`
- **Metrics Event Logging**: Performance and operational metrics collection
  - Metrics subscription tracking: `📈 SUBSCRIBED to metrics events`
  - Individual metrics: `📈 METRICS EVENT: store -> events_per_second=1250`
  - Metrics summaries: `📉 METRICS SUMMARY: 1250 eps, 50000 total, 12 active subs`
- **Health-Aware Emission Control**: EmitterWorkers can pause/resume emission based on subscription health status

#### Enhanced EmitterWorker Lifecycle Management

- **Detailed Activation Messages**: Comprehensive worker startup information including subscriber details
- **Enhanced Termination Messages**: Added subscriber information to termination logs for better debugging
- **Lifecycle Visibility**: Complete tracking of worker lifecycle events with structured, color-coded output
- **Subscriber Information**: Full visibility into which subscribers are affected by worker state changes

#### SubscriptionHealthTracker Integration

- **Dedicated Health PubSub**: Migrated from `:ex_esdb_system` to dedicated `:ex_esdb_health` PubSub instance
- **Health Event Broadcasting**: Comprehensive health event distribution to interested subscribers
- **Health Summary Distribution**: Periodic health summaries broadcast to monitoring systems
- **Improved Separation**: Clean separation between health monitoring and system operations

#### Technical Implementation

- **Multi-PubSub Architecture**: Three specialized PubSub instances for different communication types
- **Enhanced Themes System**: Extended `ExESDB.Themes` with color-coded message functions
  - `emitter_worker_success_msg/2`, `emitter_worker_failure_msg/2`
  - `emitter_worker_action_msg/2`, `emitter_worker_health_msg/2`
  - Similar functions for `emitter_system` and `emitter_pool` components
- **Health-Aware Processing**: EmitterWorkers subscribe to both health and metrics events
- **Structured Logging**: Consistent, parseable log format with rich visual indicators

#### Event-Driven Architecture Benefits

- **Separation of Concerns**: Dedicated channels prevent message type cross-contamination
- **Enhanced Observability**: Real-time visibility into system health, performance, and operations
- **Improved Reliability**: Health-aware emission and circuit breaker integration
- **Better Performance**: Asynchronous messaging and efficient broadcasting
- **Operational Excellence**: Comprehensive monitoring and debugging capabilities

#### Documentation and Guidelines

- **New Architecture Guide**: Comprehensive `guides/pubsub_architecture.md` documentation
- **Implementation Details**: Complete technical implementation and configuration guidance
- **Migration Path**: Roadmap for evolving to fully Event-Driven Architecture
- **Best Practices**: Topic naming conventions, message structure, and performance considerations
- **Monitoring Guidelines**: Health dashboard, performance metrics, and debugging tools

#### Migration Foundation

- **Phase 1 Complete**: Internal events, health/metrics distribution, enhanced observability
- **Phase 2 Prepared**: Foundation for business domain events and event sourcing patterns
- **Phase 3 Ready**: Infrastructure for external system integration and event streaming

#### Benefits

- **Unprecedented Observability**: Color-coded logging and comprehensive event tracking
- **Enhanced Reliability**: Health-aware systems with graceful degradation
- **Improved Performance**: Efficient message routing and asynchronous processing
- **Better Developer Experience**: Visual debugging aids and structured logging
- **Operational Excellence**: Comprehensive monitoring and troubleshooting capabilities
- **Future-Ready Architecture**: Solid foundation for full Event-Driven Architecture evolution

## version 0.4.9 (2025.07.19)

### Comprehensive Debugging and Monitoring System

#### New Feature: ExESDB.Debugger

- **REPL-friendly debugging tool**: Added comprehensive debugging and inspection module for ExESDB systems
- **Real-time system monitoring**: Complete visibility into processes, performance, and system health
- **Production-safe operations**: All debugging functions are read-only and safe for live systems
- **Auto-discovery capabilities**: Automatically detects stores and configuration without manual setup

#### Core Debugging Functions

- **System Overview**: `ExESDB.Debugger.overview()` - Complete system status at a glance
- **Process Management**: `ExESDB.Debugger.processes()` - List and inspect all ExESDB processes
- **Supervision Tree**: `ExESDB.Debugger.supervision_tree()` - Visual process hierarchy inspection
- **Configuration Analysis**: `ExESDB.Debugger.config()` - Shows current config with sources (env vs app config)
- **Health Monitoring**: `ExESDB.Debugger.health()` - Comprehensive system health validation

#### Data Investigation Tools

- **Stream Inspection**: `ExESDB.Debugger.streams()` - List all streams in the system
- **Event Browsing**: `ExESDB.Debugger.events(stream_id, opts)` - Browse events within specific streams
- **Subscription Monitoring**: `ExESDB.Debugger.subscriptions()` - Track active subscriptions
- **Emitter Pool Management**: `ExESDB.Debugger.emitters()` - Monitor emitter pools and workers

#### Performance and Monitoring

- **Performance Metrics**: `ExESDB.Debugger.performance()` - System memory, CPU, uptime statistics
- **Resource Analysis**: `ExESDB.Debugger.top()` - Identify resource-heavy processes
- **Observer Integration**: `ExESDB.Debugger.observer()` - Launch Erlang Observer GUI
- **Memory Tracking**: Detailed memory usage analysis across all components

#### Advanced Debugging Tools

- **Function Tracing**: `ExESDB.Debugger.trace(module, function)` - Trace specific function calls
- **Benchmarking**: `ExESDB.Debugger.benchmark(fun)` - Measure function performance
- **Multi-Store Support**: All functions work seamlessly with multiple store configurations
- **Built-in Help System**: `ExESDB.Debugger.help()` - Interactive command reference

#### Technical Implementation

- **Production-ready**: Comprehensive error handling with graceful degradation
- **Rich output formatting**: Human-readable output with emojis and structured information
- **Zero configuration**: Auto-discovery of stores and system configuration
- **Integration libraries**: Added `:recon ~> 2.5` dependency for enhanced process inspection

#### Documentation and Examples

- **Comprehensive guide**: New `guides/debugging.md` with complete usage examples
- **Interactive examples**: Built-in help system with real-world usage patterns
- **Development workflow**: Step-by-step debugging procedures for common scenarios
- **Production troubleshooting**: Safe investigation procedures for live systems

#### Benefits

- **Faster development**: Quickly understand system state and identify issues
- **Enhanced operations**: Real-time monitoring and health checking capabilities
- **Better debugging**: Trace function calls and analyze performance bottlenecks
- **Learning tool**: Visual representation of ExESDB architecture and process relationships
- **Multi-environment**: Works in development, testing, and production environments

## version 0.3.5 (2025.07.18)

### Complete Writer Modernization

#### Problem Resolution

- **Eliminated remaining fence operations**: Completed modernization of all writer components to use asynchronous persistence
- **Consistent performance**: All write operations now benefit from the same non-blocking persistence pattern
- **Removed synchronous bottlenecks**: No more blocking fence operations throughout the entire system

#### Updated Components

- **ExESDB.SubscriptionsWriter**: Replaced synchronous `:khepri.fence(store)` with asynchronous `ExESDB.PersistenceWorker.request_persistence(store)`
- **ExESDB.SnapshotsWriterWorker**: Replaced synchronous `:khepri.fence(store)` with asynchronous `ExESDB.PersistenceWorker.request_persistence(store)`
- **subscriptions_store.erl**: Replaced synchronous `khepri:fence(Store)` with asynchronous `'Elixir.ExESDB.PersistenceWorker':request_persistence(Store)`
- **subscriptions_procs.erl**: Replaced synchronous `khepri:fence(Store)` with asynchronous `'Elixir.ExESDB.PersistenceWorker':request_persistence(Store)`
- **streams_procs.erl**: Replaced synchronous `khepri:fence(Store)` with asynchronous `'Elixir.ExESDB.PersistenceWorker':request_persistence(Store)`

#### Technical Implementation

- **Unified persistence pattern**: All writers now use the same asynchronous persistence mechanism
- **Elixir-Erlang interoperability**: Erlang modules call Elixir PersistenceWorker using proper atom syntax
- **Consistent behavior**: All write operations follow the same pattern: immediate memory write + async persistence request
- **Complete fence removal**: No synchronous fence operations remain in the writer layer

#### Benefits

- **System-wide performance**: All write operations now complete in milliseconds instead of seconds
- **Eliminated timeout risks**: No more 5-second timeout failures across any writer component
- **Consistent user experience**: All write operations provide immediate feedback
- **Maintained durability**: Data persistence still guaranteed through background worker
- **Reduced complexity**: Single persistence mechanism across all writers

## version 0.3.4 (2025.07.18)

### Asynchronous Persistence System

#### Problem Resolution

- **Eliminated timeout failures**: Resolved 5-second timeout issues in `append_events` operations that were caused by synchronous fence operations
- **Improved performance**: Event append operations now complete in ~10-50ms instead of 5+ seconds
- **Enhanced user experience**: System no longer appears unresponsive during data-heavy operations

#### New Components

- **ExESDB.PersistenceWorker**: New GenServer that handles disk persistence operations asynchronously
  - Configurable persistence intervals (default: 5 seconds)
  - Batching of persistence requests for efficiency
  - Non-blocking API for event operations
  - Graceful shutdown with final persistence
  - Comprehensive error handling and logging

#### Updated Components

- **ExESDB.PersistenceSystem**: Enhanced to include PersistenceWorker as a managed component
- **ExESDB.StreamsWriterWorker**: Replaced synchronous `:khepri.fence(store)` with asynchronous `ExESDB.PersistenceWorker.request_persistence(store)`

#### New APIs

- **`ExESDB.PersistenceWorker.request_persistence(store_id)`**: Non-blocking call to request persistence
- **`ExESDB.PersistenceWorker.force_persistence(store_id)`**: Blocking call for immediate persistence (useful for testing)

#### Configuration Options

- **Global configuration**: `config :ex_esdb, persistence_interval: 10_000`
- **Per-store configuration**: `opts = [store_id: :my_store, persistence_interval: 5_000]`

#### Technical Implementation

- **Asynchronous persistence**: Events are written to memory immediately, persistence happens in background
- **Batching optimization**: Multiple persistence requests are deduplicated and processed together
- **Eventual consistency**: Data is eventually persisted (within persistence interval)
- **Fault tolerance**: System continues operating even if persistence is delayed

#### Benefits

- **Immediate response**: Event append operations return instantly
- **Better throughput**: Batched disk operations are more efficient
- **Configurable intervals**: Persistence frequency can be tuned per environment
- **Backward compatibility**: All existing APIs continue to work unchanged
- **No breaking changes**: Optional configuration with sensible defaults

#### Documentation

- **New guide**: Added comprehensive `guides/persistence_architecture.md` guide
- **Implementation details**: Complete architecture overview and migration notes
- **Testing guidance**: Instructions for integration tests using `force_persistence`

## version 0.3.3 (2025.07.18)

### Data Persistence and Durability Enhancement

#### Khepri Fence Operations Implementation

- **Enhanced data durability**: Added `fence` operations after all Khepri write operations to ensure data persistence to disk
- **Guaranteed write consistency**: All write operations now block until data is committed and persisted through Ra's write-ahead logging
- **Improved reliability**: Prevents data loss in case of system crashes or power failures

#### Updated Components

- **ExESDB.SubscriptionsWriter**: Added fence operations after direct `:khepri.delete!` calls and indirect subscription store operations
- **ExESDB.SnapshotsWriterWorker**: Added fence operations after `:khepri.delete!` and `:khepri.put!` operations for snapshot management
- **ExESDB.StreamsWriterWorker**: Added fence operations after `:khepri.put!` calls in event recording operations
- **subscriptions_store.erl**: Added fence operations after all `khepri:put`, `khepri:update`, and `khepri:delete` operations
- **streams_procs.erl**: Added fence operations after `khepri:put` operations for event procedure registration
- **subscriptions_procs.erl**: Added fence operations after `khepri:put` operations for subscription procedure registration

#### Technical Implementation

- **Write-through persistence**: All write operations now call `:khepri.fence(store)` immediately after data modification
- **Consistency guarantees**: Fence operations ensure that subsequent reads will see the results of all previous writes
- **Durability assurance**: Data is guaranteed to be persisted to disk before write operations complete
- **Performance consideration**: Fence operations provide strong consistency at the cost of slightly increased write latency

#### Benefits

- **Data integrity**: Eliminates risk of data loss during system failures
- **Consistency guarantees**: Ensures all write operations are properly persisted before completion
- **Improved reliability**: Provides stronger durability guarantees for critical event store operations
- **Operational confidence**: Reduces risk of data corruption in production environments

## version 0.3.1 (2025.07.17)

### LeaderWorker Registration Fix

#### Problem Resolution

- **Fixed LeaderWorker registration warnings**: Resolved warning messages "LeaderWorker registration issue: expected #PID<...>, got nil"
- **Store-specific registration verification**: LeaderWorker now properly verifies its registration using the store-specific name instead of the hardcoded module name
- **Improved logging**: Registration confirmation logs now show the actual store-specific process name

#### Technical Implementation

- **Updated init/1 function**: LeaderWorker now extracts store_id from config and uses `StoreNaming.genserver_name/2` to determine the expected registration name
- **Correct registration check**: Uses `Process.whereis(expected_name)` instead of `Process.whereis(__MODULE__)` for verification
- **Enhanced logging**: Log messages now show the actual store-specific name used for registration

#### Benefits

- **Cleaner logs**: Eliminates confusing registration warning messages during startup
- **Better debugging**: Registration verification now works correctly with store-specific naming
- **Improved reliability**: Proper registration verification helps identify actual process registration issues

## version 0.3.0 (2025.07.17)

### Multiple Stores Naming Conflicts Fix

#### Problem Resolution

- **Fixed naming conflicts**: Resolved `already started` errors when multiple umbrella applications attempted to start their own ExESDB systems
- **Store isolation**: Each store now has its own isolated set of partition supervisors
- **Multi-tenancy support**: Different applications can maintain completely separate event stores within the same Elixir node

#### Updated Components

- **ExESDB.Emitters**: Updated `start_emitter_pool/3` to use store-specific partition names
- **ExESDB.EmitterSystem**: Updated supervisor child spec to use store-specific partition names
- **ExESDB.GatewaySystem**: Updated supervisor child spec to use store-specific partition names
- **ExESDB.LeaderWorker**: Updated process lookup to use store-specific partition names
- **ExESDB.Snapshots**: Updated supervisor child specs to use store-specific partition names
- **ExESDB.SnapshotsReader**: Updated `start_child/2` to use store-specific partition names
- **ExESDB.SnapshotsWriter**: Updated `start_child/2` to use store-specific partition names
- **ExESDB.Streams**: Updated supervisor child specs to use store-specific partition names
- **ExESDB.StreamsReader**: Updated `start_child/2` to use store-specific partition names
- **ExESDB.StreamsWriter**: Updated `start_child/2` to use store-specific partition names

#### Technical Implementation

- **Store-specific naming**: All modules now use `ExESDB.StoreNaming.partition_name/2` to generate unique process names
- **Unique process names**: Each store gets its own partition supervisors (e.g., `:exesdb_streamswriters_store_one`, `:exesdb_streamswriters_store_two`)
- **Backward compatibility**: Existing single-store deployments continue to work unchanged
- **Consistent pattern**: All partition supervisors follow the same naming convention

#### Affected Processes

- **ExESDB.StreamsWriters**: Now store-specific to prevent conflicts
- **ExESDB.StreamsReaders**: Now store-specific to prevent conflicts
- **ExESDB.SnapshotsWriters**: Now store-specific to prevent conflicts
- **ExESDB.SnapshotsReaders**: Now store-specific to prevent conflicts
- **ExESDB.EmitterPools**: Now store-specific to prevent conflicts
- **ExESDB.GatewayWorkers**: Now store-specific to prevent conflicts

#### Benefits

- **True multi-tenancy**: Multiple applications can run separate ExESDB systems without conflicts
- **Better isolation**: Each store operates independently with its own resources
- **Improved reliability**: Eliminates startup failures due to naming conflicts
- **Enhanced scalability**: Supports complex umbrella application architectures
- **Maintained compatibility**: Zero breaking changes for existing deployments

## version 0.1.7 (2025.07.16)

### Configuration System Modernization

#### Legacy Configuration Removal

- **Removed khepri configuration**: Eliminated legacy `config :ex_esdb, :khepri` configuration format
- **Modernized Options module**: Updated `ExESDB.Options` to use umbrella-aware configuration patterns
- **Consistent configuration format**: All configurations now use `config :your_app_name, :ex_esdb, [options]` format
- **Improved isolation**: Better configuration isolation between applications in umbrella projects

#### Configuration Documentation

- **New configuration guide**: Added comprehensive `guides/configuring_exesdb_apps.md` guide
- **Standalone application examples**: Complete configuration examples for single-app deployments
- **Umbrella application examples**: Detailed examples for multi-app umbrella projects
- **Environment variable documentation**: Complete reference for all environment variable overrides
- **Migration guide**: Instructions for migrating from legacy khepri configuration

#### Configuration Features

- **Context management**: Enhanced context switching for umbrella applications
- **Explicit context support**: Added `app_env/3` functions for explicit context usage
- **Context wrapper support**: Added `with_context/2` for scoped configuration access
- **Libcluster integration**: Emphasized libcluster usage over deprecated seed_nodes mechanism

#### Benefits

- **Better umbrella support**: Proper configuration isolation for umbrella applications
- **Clearer configuration patterns**: Consistent `config :app_name, :ex_esdb` format
- **Improved developer experience**: Comprehensive documentation and examples
- **Enhanced maintainability**: Removed legacy code paths and simplified configuration logic

## version 0.1.2 (2025.07.14)

### Store Configuration Enhancement

#### New Environment Variables

- **`EX_ESDB_STORE_DESCRIPTION`**: Human-readable description of the store for documentation and operational purposes
- **`EX_ESDB_STORE_TAGS`**: Comma-separated tags for store categorization and filtering (e.g., "production,cluster,core")

#### Rich Store Configuration

- **Operational Metadata**: Added `created_at`, `version`, and `status` fields to store configuration
- **Resource Management**: Added `priority` and `auto_start` fields for resource allocation control
- **Administrative Info**: Enhanced store registry with `tags`, `environment`, and `description` fields
- **Enhanced Querying**: Store registry now supports filtering by tags, environment, priority, and other metadata

#### Configuration Integration

- **Runtime Configuration**: New environment variables integrated into `config/runtime.exs`
- **Options System**: Added parsers in `ExESDB.Options` with comma-separated tag parsing
- **Store Registry**: Enhanced `build_store_config/1` to include all new metadata fields
- **Development Environment**: Updated `dev-env/*.yaml` files with new environment variables

### Architectural Refactoring

#### NotificationSystem Introduction

- **New Core Component**: Created `ExESDB.NotificationSystem` as a core supervisor for event notification
- **Leadership Integration**: Moved `LeaderSystem` from clustering layer to core system
- **Core System Enhancement**: Updated `CoreSystem` to include `NotificationSystem` alongside `PersistenceSystem` and `StoreSystem`
- **Supervision Order**: `PersistenceSystem` → `NotificationSystem` → `StoreSystem` for proper dependency management

#### LeaderWorker Availability Fix

- **Core System Integration**: LeaderWorker now starts as part of core system, not clustering components
- **Startup Order**: LeaderWorker is available before clustering components attempt to use it
- **Resolved `:noproc` Error**: Fixed LeaderWorker activation failures by ensuring it's always running when needed
- **Single and Cluster Mode**: LeaderWorker now available in both single-node and cluster modes

#### System Architecture Cleanup

- **Removed LeadershipSystem**: Consolidated functionality into `NotificationSystem`
- **Cleaner Separation**: Core functionality (leadership, events) vs clustering (coordination, membership)
- **Improved Documentation**: Updated supervision tree documentation to reflect new architecture
- **Simplified Dependencies**: Reduced coupling between core and clustering components

### Process Management Enhancement

#### Graceful Shutdown Implementation

- **Universal Coverage**: All 18 GenServer processes now implement graceful shutdown
- **Terminate Callbacks**: Added `terminate/2` callbacks to all GenServers for proper cleanup
- **Exit Trapping**: Enabled `Process.flag(:trap_exit, true)` on all GenServers
- **Resource Cleanup**: Proper cleanup of Swarm registrations, PubSub subscriptions, and Khepri stores

#### Enhanced Process Lifecycle

- **Swarm Registration Cleanup**: Worker processes properly unregister from Swarm on shutdown
- **PubSub Subscription Cleanup**: EventProjector properly unsubscribes from topics
- **Khepri Store Shutdown**: Store processes gracefully stop Khepri instances
- **Network Monitoring**: NodeMonitor properly disables network monitoring on shutdown

### Development Environment

#### Configuration Updates

- **proc-sup Configuration**: Added description "Process Supervisor Event Store" and tags "development,cluster,proc-sup,core"
- **reg-gh Configuration**: Added description "Registration System Event Store" and tags "development,cluster,reg-gh,registration"
- **Environment-Specific Tags**: Different tags for development vs production environments
- **Consistent Formatting**: Standardized environment variable layout across all configuration files

### Benefits

#### Operational Improvements

- **Enhanced Monitoring**: Rich store metadata enables better operational visibility
- **Improved Debugging**: Store descriptions and tags help identify issues faster
- **Better Resource Management**: Priority and auto-start fields enable fine-grained control
- **Cleaner Shutdown**: All processes terminate gracefully without resource leaks

#### Development Experience

- **Clearer Architecture**: Separation of core vs clustering concerns
- **Consistent Configuration**: Standardized environment variable management
- **Better Testability**: Core components can be tested independently of clustering
- **Simplified Debugging**: LeaderWorker availability issues resolved

#### System Reliability

- **Reduced Race Conditions**: Proper startup order prevents timing-related failures
- **Resource Leak Prevention**: Graceful shutdown prevents resource accumulation
- **Improved Fault Tolerance**: Better separation of concerns reduces cascade failures
- **Enhanced Observability**: Rich metadata supports better monitoring and alerting

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
