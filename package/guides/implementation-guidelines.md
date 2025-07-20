# General Implementation Guidelines for Reckon_* Applications

## Introduction: Why Vertical Slicing and Screaming Architecture?

Traditional layered architectures organize code by **technical concerns**—controllers, services, repositories, models. This approach creates several problems:

### Problems with Layered Architecture
1. **Scattered Business Logic**: A single business operation spans multiple layers and directories
2. **Cognitive Overhead**: Developers must navigate between layers to understand one feature
3. **Tight Coupling**: Changes often require modifications across multiple layers
4. **Testing Complexity**: Integration tests become necessary to verify simple business operations
5. **Team Conflicts**: Multiple developers working on the same layers create merge conflicts
6. **Hidden Business Intent**: The codebase doesn't reveal what the system actually does

### Why We Chose Vertical Slicing
**Vertical slicing** organizes code by **business capabilities** instead of technical layers. Each business operation becomes a self-contained "slice" with everything it needs:

- **Single Source of Truth**: All code for one business operation lives together
- **Reduced Cognitive Load**: Developers see the complete feature in one place
- **Independent Evolution**: Features can change without affecting others
- **Simplified Testing**: Each slice can be tested in isolation
- **Team Autonomy**: Different teams can own different slices
- **Business Alignment**: Code structure mirrors how the business thinks

### Why We Chose Screaming Architecture
**Screaming Architecture** (Uncle Bob's term) means your codebase "screams" its business intent. When someone looks at the folder structure, they immediately understand:

- **What the system does** (not how it's implemented)
- **What business operations exist** (initialize_account, cast_vote)
- **What the domain is about** (voting, accounts, profiles)

Instead of seeing generic technical folders like `controllers/`, `services/`, `models/`, you see business-focused folders like `initialize_poll/`, `cast_vote/`, `activate_account/`.

### Real-World Benefits
This architecture has proven benefits in production systems:

- **Faster Onboarding**: New developers understand the system quickly
- **Reduced Bugs**: Business logic stays cohesive and isolated
- **Better Documentation**: The code structure IS the documentation
- **Easier Refactoring**: Changes are localized to specific slices
- **Business Conversations**: Non-technical stakeholders can navigate the codebase

## Architecture Philosophy

### Vertical Slicing Architecture
The reckon_* applications follow a **vertical slicing architecture** where each business operation (use case) is implemented as a self-contained slice that includes all necessary components:

- **Command**: Input structure defining the operation
- **Event**: Output structure representing what happened
- **Handler**: Business logic processing the command and emitting events
- **Projections**: Read models updated by events (when needed)

This approach ensures that each business capability is:
- **Isolated**: Changes to one slice don't affect others
- **Cohesive**: All related code is co-located
- **Testable**: Each slice can be tested independently
- **Discoverable**: Business operations are obvious from the folder structure

### Screaming Architecture
The codebase "screams" its business intent through:

1. **Directory Structure**: Business operations are immediately visible as top-level folders
2. **Module Names**: Clearly express business concepts, not technical layers
3. **File Organization**: Business logic is organized by use case, not by technical pattern

## 🔥 MANDATORY Event Storming Requirement

**RULE**: Each new project MUST start with an initial Event Storming session, of which the result will be written in the apps `./design_docs/event-storming.md` document.

This document is a timestamped log of event storming sessions and will contain the following sections:

1. **Executive Summary** (a description of the process under design)
2. **ASCII diagram** that depicts the commands, the policies they are called from, the events they emit
3. **ASCII code structure diagram**
4. **Description of each slice**

The event storming document serves as the foundation for implementing the vertical slicing architecture and ensures all stakeholders understand the business processes before development begins.

## 🔥 STRICT VERSIONING RULES

**These rules are MANDATORY and MUST be followed without exception:**

### 1. All Commands and Events MUST Have Versions
- **Commands**: `InitializePollV1`, `CastVoteV1`
- **Events**: `PollInitializedV1`, `VoteCastedV1`
- **Event Type Strings**: `"poll_initialized:v1"`, `"vote_casted:v1"`

### 2. Directory Names Are Clean (No Version Suffix)
- **Format**: `[command_name]/` (no version in directory name)
- **Examples**: `initialize_poll/`, `cast_vote/`, `activate_account/`
- **Rationale**: Prevents unwieldy module names like `InitializePollV1.CommandV1`

### 3. File Names MUST Include Version
- **Files**: `command_v1.ex`, `event_v1.ex`, `maybe_initialize_poll_v1.ex`
- **Event Handlers**: `initialized_to_state_v1.ex`, `casted_to_summary_v1.ex`
- **Projections**: `initialized_to_summary_v1.ex`
- **Evolution**: V2 files coexist in same directory: `command_v2.ex`, `event_v2.ex`

### 4. 🚫 FORBIDDEN: CRUD Events
**CRUD events have NO business meaning and are STRICTLY FORBIDDEN:**

**❌ FORBIDDEN CRUD Events:**
- `PollCreated`, `AccountUpdated`, `UserDeleted`
- `ProfileCreated`, `MembershipUpdated`
- Any event ending in `-Created`, `-Updated`, `-Deleted`

**✅ REQUIRED: Business-Meaningful Events:**
- `PollInitialized`, `AccountActivated`, `UserSuspended`
- `ProfileEstablished`, `MembershipGranted`, `MembershipExpired`
- Events that express **business intent and meaning**

## Project Structure

```
reckon_[domain]/
├── lib/
│   ├── reckon_[domain]/
│   │   ├── application.ex           # OTP application bootstrap
│   │   ├── repo.ex                  # Ecto repository for read models
│   │   ├── router.ex                # Commanded router for command dispatch
│   │   ├── shared/
│   │   │   └── [aggregate].ex       # Domain aggregate root
│   │   │
│   │   ├── domain/                  # 🔥 LITERAL "domain" directory (invariant)
│   │   │   ├── [command_name]/      # 🔥 VERTICAL SLICE (named after COMMAND)
│   │   │   │   ├── command.ex       # Command structure (input)
│   │   │   │   ├── event.ex         # Event structure (output)
│   │   │   │   ├── handler.ex       # Command handler (business logic)
│   │   │   │   ├── [event]_to_state.ex                    # Event handler (aggregate updates)
│   │   │   │   ├── [event]_to_[readmodel].ex              # Projection (optional)
│   │   │   │   └── when_[event]_then_[command].ex         # Policy (optional)
│   │   │   │
│   │   │   └── [another_command]/   # Another vertical slice
│   │   │       ├── command.ex
│   │   │       ├── event.ex
│   │   │       ├── handler.ex
│   │   │       ├── [event]_to_state.ex
│   │   │       └── ...
│   │   │
│   │   └── projections/             # Cross-cutting read models (if needed)
│   │       └── [projection_name].ex
│   │
│   ├── reckon_[domain].ex           # Public API (business facade)
│   └── mix/
│       └── tasks/
│           ├── reckon_[domain].setup.ex
│           └── reckon_[domain].reset.ex
├── config/
│   ├── config.exs                   # Main config with ExESDB setup
│   ├── dev.exs
│   ├── test.exs
│   └── prod.exs
├── test/
├── priv/
└── mix.exs
```

## Core Principles

### 1. One Capability Per Module Strategy

**FUNDAMENTAL RULE**: We follow a strict 1-capability-per-module strategy across all components:

- **1 Command per Module**: Each command gets its own dedicated module
- **1 Event per Module**: Each event gets its own dedicated module  
- **1 Handler per Module**: Each handler processes one command type
- **1 Projection per Module**: Each projection handles one event type to one read model
- **1 Policy per Module**: Each policy (process manager) handles one event-to-command translation

This ensures maximum cohesion, testability, and discoverability.

### 2. Each Command/Event Must Reside in Its Own Module

**❌ WRONG - Grouping multiple commands/events in one module:**
```elixir
defmodule ReckonProfiles.Commands do
  defmodule CreateProfile do
    # ...
  end
  
  defmodule UpdateProfile do
    # ...
  end
end
```

**✅ CORRECT - Each command/event in its own dedicated module:**
```elixir
# lib/reckon_profiles/create_profile/command.ex
defmodule ReckonProfiles.CreateProfile.Command do
  # ...
end

# lib/reckon_profiles/update_profile/command.ex
defmodule ReckonProfiles.UpdateProfile.Command do
  # ...
end
```

### 3. Vertical Slice Structure

Each business operation follows this exact pattern:

```
domain/
└── [command_name]/                      # 🔥 SLICE named after COMMAND (no version)
    ├── command_v1.ex                    # Input structure - what the user wants to do
    ├── event_v1.ex                      # Output structure - what actually happened
    ├── maybe_[command]_v1.ex            # Command handler - business logic
    ├── [event]_to_state_v1.ex           # Event handler - aggregate state updates
    ├── [event]_to_[readmodel]_v1.ex     # Projection (optional)
    ├── when_[event]_then_[command]_v1.ex # Policy (optional)
    │
    # V2 Evolution (coexists in same directory)
    ├── command_v2.ex                    # Updated command structure
    ├── event_v2.ex                      # Updated event structure
    └── maybe_[command]_v2.ex            # Updated command handler
```

**Key Points:**
- All slices go under the literal `domain/` directory
- Slices are named after the **command** they contain (not the business operation)
- `maybe_[command].ex` = **Command Handler** (processes commands, emits events)
- `[event]_to_state.ex` = **Event Handler** (applies events to aggregate state)
- Policies go in the slice where the **command** they trigger is located

### 4. Strict Projection Naming Convention

**MANDATORY FORMAT**: Projections MUST be named using the exact format `<event>_to_<readmodel>.ex`

**Rules:**
- Projections belong in the same slice as the event they process
- File name format: `[lowercase_event_name]_to_[readmodel_name].ex`
- Module name format: `Domain.BusinessOperation.EventToReadmodel`
- Each projection handles exactly ONE event type to ONE read model

**Examples:**
```
# File: lib/reckon_accounts/initialize_account/initialized_to_summary.ex
# Module: ReckonAccounts.InitializeAccount.InitializedToSummary
# Processes: AccountInitialized → AccountSummary

# File: lib/reckon_profiles/establish_profile/established_to_directory.ex
# Module: ReckonProfiles.EstablishProfile.EstablishedToDirectory
# Processes: ProfileEstablished → ProfileDirectory
```

### 5. Policy (Process Manager) Pattern

**Purpose**: Policies translate events into commands and dispatch them through CommandedApp.

**Rules:**
- Policies belong in the slice where the **command** they trigger is located
- File name format: `when_<event>_then_<command>.ex`
- Module name format: `Domain.CommandName.When<Event>Then<Command>`
- Each policy handles ONE event type and dispatches ONE command type
- **MANDATORY**: All command dispatching MUST go through `CommandedApp.dispatch/1`

**Policy Structure:**
```elixir
# File: lib/reckon_profiles/domain/establish_profile/when_account_activated_then_establish_profile.ex
defmodule ReckonProfiles.Domain.EstablishProfile.WhenAccountActivatedThenEstablishProfile do
  @moduledoc """
  Policy that triggers profile establishment when an account is activated.
  
  This policy listens to AccountActivated events and automatically
  dispatches an EstablishProfile command to the profiles domain.
  """
  
  use Commanded.Event.Handler,
    application: ReckonProfiles.CommandedApp,
    name: "when_account_activated_then_establish_profile"
  
  alias ReckonAccounts.Domain.ActivateAccount.Event, as: AccountActivated
  alias ReckonProfiles.Domain.EstablishProfile.Command, as: EstablishProfileCommand
  alias ReckonProfiles.CommandedApp
  
  def handle(%AccountActivated{} = event, _metadata) do
    command = %EstablishProfileCommand{
      account_id: event.account_id,
      email: event.email,
      requested_at: DateTime.utc_now()
    }
    
    # MANDATORY: Dispatch through CommandedApp
    CommandedApp.dispatch(command)
  end
end
```

**Key Policy Placement Rule:**
- The policy goes in the slice of the **command** it triggers, not the event it listens to
- This makes sense because the policy is about **causing** that command to be executed

## Concrete Examples

To make the new structure crystal clear, here are concrete examples:

### Example: ReckonProfiles Domain Structure

```
reckon_profiles/
├── lib/
│   ├── reckon_profiles/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── router.ex
│   │   ├── shared/
│   │   │   └── profile.ex                        # Profile aggregate
│   │   │
│   │   ├── domain/                              # 🔥 LITERAL "domain" directory
│   │   │   ├── establish_profile/              # Command slice
│   │   │   │   ├── command.ex                   # EstablishProfile command
│   │   │   │   ├── event.ex                     # ProfileEstablished event
│   │   │   │   ├── handler.ex                   # Command handler
│   │   │   │   ├── established_to_state.ex     # Event handler (ProfileEstablished → Profile aggregate)
│   │   │   │   ├── established_to_directory.ex # Projection (ProfileEstablished → ProfileDirectory)
│   │   │   │   └── when_account_activated_then_establish_profile.ex  # Policy
│   │   │   │
│   │   │   ├── update_profile/                 # Another command slice
│   │   │   │   ├── command.ex                   # UpdateProfile command
│   │   │   │   ├── event.ex                     # ProfileUpdated event
│   │   │   │   ├── handler.ex                   # Command handler
│   │   │   │   ├── updated_to_state.ex         # Event handler
│   │   │   │   └── updated_to_directory.ex     # Projection
│   │   │   │
│   │   │   └── deactivate_profile/
│   │   │       ├── command.ex
│   │   │       ├── event.ex
│   │   │       ├── handler.ex
│   │   │       └── deactivated_to_state.ex
│   │   │
│   │   └── projections/                        # Cross-cutting projections (if needed)
│   │       └── profile_search_projection.ex
│   │
│   ├── reckon_profiles.ex                      # Public API
│   └── ...
```

### Example: File Names and Module Names

**Command:**
- File: `lib/reckon_profiles/domain/establish_profile/command.ex`
- Module: `ReckonProfiles.Domain.EstablishProfile.Command`

**Event:**
- File: `lib/reckon_profiles/domain/establish_profile/event.ex`
- Module: `ReckonProfiles.Domain.EstablishProfile.Event`

**Command Handler:**
- File: `lib/reckon_profiles/domain/establish_profile/handler.ex`
- Module: `ReckonProfiles.Domain.EstablishProfile.Handler`

**Event Handler (to State):**
- File: `lib/reckon_profiles/domain/establish_profile/established_to_state.ex`
- Module: `ReckonProfiles.Domain.EstablishProfile.EstablishedToState`

**Projection:**
- File: `lib/reckon_profiles/domain/establish_profile/established_to_directory.ex`
- Module: `ReckonProfiles.Domain.EstablishProfile.EstablishedToDirectory`

**Policy:**
- File: `lib/reckon_profiles/domain/establish_profile/when_account_activated_then_establish_profile.ex`
- Module: `ReckonProfiles.Domain.EstablishProfile.WhenAccountActivatedThenEstablishProfile`

### Key Naming Rules Summary

1. **Directory Structure**: `reckon_[domain]/lib/reckon_[domain]/domain/[command_name]/`
2. **Slice Names**: Named after the **command** (not the business operation)
3. **Handler Types**:
   - `maybe_[command].ex` = Command Handler
   - `[event]_to_state.ex` = Event Handler (aggregate updates)
4. **Projections**: `[event]_to_[readmodel].ex` (in slice with event)
5. **Policies**: `when_[event]_then_[command].ex` (in slice with command they trigger)
6. **Module Naming**: `ReckonDomain.Domain.CommandName.FileType`

### 6. Screaming Business Intent

Folder names should express **business operations**, not technical concepts:

**✅ GOOD - Business-focused names:**
- `initialize_account/`
- `verify_email/`
- `create_profile/`
- `update_profile_picture/`
- `close_account/`

**❌ BAD - Technical-focused names:**
- `commands/`
- `events/`
- `handlers/`
- `controllers/`
- `services/`

## Module Naming Conventions

### Command Modules
```elixir
defmodule ReckonProfiles.CreateProfile.Command do
  @moduledoc """
  Command to create a new user profile.
  
  This command is triggered when a user completes their initial
  profile setup after account verification.
  """
  
  defstruct [
    :account_id,
    :display_name,
    :bio,
    :requested_at
  ]
  
  @type t :: %__MODULE__{
    account_id: String.t(),
    display_name: String.t(),
    bio: String.t() | nil,
    requested_at: DateTime.t()
  }
end
```

### Event Modules
```elixir
defmodule ReckonProfiles.CreateProfile.Event do
  @moduledoc """
  Event emitted when a profile is successfully created.
  
  This event triggers read model updates and may trigger
  other domain reactions.
  """
  
  @derive Jason.Encoder
  defstruct [
    :account_id,
    :display_name,
    :bio,
    :created_at,
    :version
  ]
  
  @type t :: %__MODULE__{
    account_id: String.t(),
    display_name: String.t(),
    bio: String.t() | nil,
    created_at: DateTime.t(),
    version: integer()
  }
end
```

### Handler Modules
```elixir
defmodule ReckonProfiles.CreateProfile.Handler do
  @moduledoc """
  Command handler for CreateProfile command.
  
  Business rules:
  - Profile can only be created once per account
  - Display name must be unique
  - Bio is optional but limited to 500 characters
  """
  
  alias ReckonProfiles.Shared.Profile
  alias ReckonProfiles.CreateProfile.{Command, Event}
  
  def execute(%Profile{account_id: nil}, %Command{} = command) do
    # Business logic here
    %Event{
      account_id: command.account_id,
      display_name: command.display_name,
      bio: command.bio,
      created_at: command.requested_at,
      version: 1
    }
  end
  
  def execute(%Profile{}, %Command{}) do
    {:error, :profile_already_exists}
  end
  
  def apply(%Profile{} = profile, %Event{} = event) do
    # State updates here
    %Profile{profile |
      account_id: event.account_id,
      display_name: event.display_name,
      bio: event.bio,
      created_at: event.created_at,
      updated_at: event.created_at
    }
  end
end
```

## Technical Configuration

### Dependencies (mix.exs)
```elixir
defp deps do
  [
    {:dns_cluster, "~> 0.1.1"},
    {:phoenix_pubsub, "~> 2.1"},
    {:ecto_sql, "~> 3.10"},
    {:ecto_sqlite3, ">= 0.0.0"},
    {:jason, "~> 1.2"},
    {:ex_esdb, "~> 0.1.4"},
    {:ex_esdb_commanded, "0.1.3"}
  ]
end
```

### ExESDB Configuration (config/config.exs)
```elixir
# Configure ExESDB for ReckonProfiles
config :ex_esdb, :khepri,
  data_dir: "tmp/reckon_profiles",
  store_id: :reckon_profiles,  # 🔥 UNIQUE per domain
  timeout: 10_000,
  db_type: :single,
  pub_sub: :ex_esdb_pubsub,
  store_description: "Reckon Profiles Event Store",
  store_tags: ["reckon", "profiles", "event-sourcing", "development"]

# Configure the Commanded application
config :reckon_profiles, ReckonProfiles.CommandedApp,
  event_store: [
    adapter: ExESDB.Commanded.Adapter,
    store_id: :reckon_profiles,
    stream_prefix: "reckon_profiles_",  # 🔥 UNIQUE per domain
    serializer: Jason,
    event_type_mapper: ReckonProfiles.EventTypeMapper
  ]
```

### LibCluster Configuration (User Preference)
```elixir
# Configure libcluster (preferred over seed_nodes)
config :libcluster,
  topologies: [
    reckon_profiles: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45_894,  # 🔥 UNIQUE per domain
        if_addr: "0.0.0.0",
        multicast_addr: "255.255.255.255",
        broadcast_only: true,
        secret: System.get_env("RECKON_PROFILES_CLUSTER_SECRET") || "reckon_profiles_cluster_secret"
      ]
    ]
  ]
```

## Public API Pattern

The main module provides a business-focused API:

```elixir
defmodule ReckonProfiles do
  @moduledoc """
  ReckonProfiles domain - User profile management and personalization.
  
  This module provides the public API for profile operations including:
  - Profile creation and updates
  - Profile picture management
  - Privacy settings
  
  Uses vertical slicing architecture where each command has its own slice
  containing command, events, and handlers.
  """
  
  alias ReckonProfiles.CommandedApp
  
  @doc """
  Creates a new user profile.
  
  This is typically called after account verification is complete.
  """
  def create_profile(account_id, display_name, bio \\ nil) do
    command = %ReckonProfiles.CreateProfile.Command{
      account_id: account_id,
      display_name: display_name,
      bio: bio,
      requested_at: DateTime.utc_now()
    }
    
    CommandedApp.dispatch(command)
  end
  
  # ... other business operations
end
```

## Key Benefits of This Architecture

1. **Discoverability**: New developers can immediately understand what the system does by looking at folder names
2. **Maintainability**: Changes to one business operation don't affect others
3. **Testability**: Each slice can be unit tested independently
4. **Scalability**: Teams can work on different slices without conflicts
5. **Business Alignment**: Code structure mirrors business processes

## Projection Naming and Organization

### Event-to-Projection Naming Pattern

Projections should use the `event_to_projection_type` naming pattern to immediately communicate their intent and relationship, following screaming architecture principles:

```
reckon_[domain]/
├── lib/
│   ├── reckon_[domain]/
│   │   ├── initialize_account/
│   │   │   ├── command.ex
│   │   │   ├── event.ex
│   │   │   ├── handler.ex
│   │   │   └── initialized_to_summary.ex    # Projection: AccountInitialized → AccountSummary
│   │   ├── activate_account/
│   │   │   ├── command.ex
│   │   │   ├── event.ex
│   │   │   ├── handler.ex
│   │   │   └── activated_to_summary.ex      # Projection: AccountActivated → AccountSummary
│   │   └── close_account/
│   │       ├── command.ex
│   │       ├── event.ex
│   │       ├── handler.ex
│   │       └── closed_to_summary.ex         # Projection: AccountClosed → AccountSummary
```

### Projection Module Naming

Projection modules should follow the same naming pattern:

```elixir
# lib/reckon_accounts/initialize_account/initialized_to_summary.ex
defmodule ReckonAccounts.InitializeAccount.InitializedToSummary do
  @moduledoc """
  Projection that handles AccountInitialized events and updates the AccountSummary read model.
  
  This projection creates new entries in the account_summaries table when accounts are initialized.
  """
  
  use Commanded.Projections.Ecto,
    application: ReckonAccounts.CommandedApp,
    repo: ReckonAccounts.Repo,
    name: "ReckonAccounts.InitializeAccount.InitializedToSummary"
  
  alias ReckonAccounts.InitializeAccount.Event, as: AccountInitialized
  alias ReckonAccounts.Schemas.AccountSummary
  
  project(%AccountInitialized{} = event, _metadata, fn multi ->
    # Projection logic here
  end)
end
```

## Testing Guidelines

### Vertical Slicing in Tests

Tests should mirror the vertical slicing architecture and include projections within their related slices:

```
reckon_[domain]/
├── test/
│   ├── reckon_[domain]/
│   │   ├── initialize_account/              # Tests for initialize_account slice
│   │   │   ├── command_test.exs
│   │   │   ├── handler_test.exs
│   │   │   ├── event_test.exs
│   │   │   └── initialized_to_summary_test.exs  # Projection test within slice
│   │   ├── activate_account/                # Tests for activate_account slice
│   │   │   ├── command_test.exs
│   │   │   ├── handler_test.exs
│   │   │   ├── event_test.exs
│   │   │   └── activated_to_summary_test.exs    # Projection test within slice
│   │   └── close_account/
│   │       ├── command_test.exs
│   │       ├── handler_test.exs
│   │       ├── event_test.exs
│   │       └── closed_to_summary_test.exs       # Projection test within slice
│   └── support/
│       └── test_helper.ex
```

### Test Isolation Principles

1. **Domain Tests Should Be Isolated**: Each domain's tests should run independently without requiring other domains to be running.

2. **Use Ecto.Adapters.SQL.Sandbox**: For database tests, use sandbox mode to ensure test isolation:

```elixir
# test/test_helper.exs
Ecto.Adapters.SQL.Sandbox.mode(ReckonAccounts.Repo, :manual)

# In test modules
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(ReckonAccounts.Repo)
end
```

3. **Test Each Slice Independently**: Write unit tests for commands, handlers, events, and projections separately within each slice.

4. **Integration Tests for Cross-Slice Interactions**: Use integration tests sparingly and only when testing interactions between slices within the same domain.

### Projection Testing Guidelines

1. **Projections Stay With Their Events**: Projections should be located in the same slice as their related events, using the `event_to_projection_type` naming pattern.

2. **Test Projections Separately**: Write dedicated tests for projections that verify:
   - Event handling and state updates
   - Database persistence
   - Error handling and recovery

3. **Use Test Fixtures**: Create test fixtures for events to ensure consistent testing:

```elixir
# test/support/fixtures.ex
defmodule ReckonAccounts.Fixtures do
  def account_initialized_event(attrs \\ %{}) do
    %ReckonAccounts.InitializeAccount.Event{
      account_id: attrs[:account_id] || "test-account-123",
      email: attrs[:email] || "test@example.com",
      initialized_at: attrs[:initialized_at] || DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
```

## Integration Between Domains

### Web Service Proxy Pattern

Integrations between domain services (`reckon_*` apps) and the website (`landing_site_web`) must go through the umbrella's web service proxy (`landing_site`). This ensures:

1. **Loose Coupling**: Domains don't directly depend on web concerns
2. **Consistent API**: All web interactions go through a single, well-defined interface
3. **Testability**: Web and domain logic can be tested independently
4. **Scalability**: Domains can be extracted to separate services later

```elixir
# ✅ Correct: Web interactions through proxy
LandingSite.Accounts.initialize_account(email, password)

# ❌ Incorrect: Direct domain access from web
ReckonAccounts.initialize_account(email, password)
```

## Integration Events (Facts) Pattern

### Facts vs Domain Events

**Domain Events** are internal to a domain and handle business logic within that domain.

**Facts** are integration events that communicate between domains. They represent immutable facts about what happened in one domain that other domains might care about.

### Facts Structure

Facts are defined in the `reckon_shared` application, organized by originating domain:

```
reckon_shared/
├── lib/
│   ├── reckon_shared/
│   │   ├── accounts/                    # Facts from reckon_accounts domain
│   │   │   ├── account_initialized_fact.ex
│   │   │   ├── account_activated_fact.ex
│   │   │   └── account_closed_fact.ex
│   │   ├── profiles/                    # Facts from reckon_profiles domain
│   │   │   ├── profile_created_fact.ex
│   │   │   └── profile_updated_fact.ex
│   │   └── memberships/                 # Facts from reckon_memberships domain
│   │       ├── membership_created_fact.ex
│   │       └── membership_expired_fact.ex
│   └── reckon_shared.ex
```

### Fact Module Pattern
```elixir
# lib/reckon_shared/accounts/account_activated_fact.ex
defmodule ReckonShared.Accounts.AccountActivatedFact do
  @moduledoc """
  Integration event (Fact) emitted when an account is activated.
  
  This fact is consumed by other domains that need to react to
  account activation, such as:
  - ReckonProfiles (to enable profile creation)
  - ReckonMemberships (to activate trial memberships)
  """
  
  @derive Jason.Encoder
  defstruct [
    :account_id,
    :email,
    :activated_at,
    :fact_id,
    :fact_version
  ]
  
  @type t :: %__MODULE__{
    account_id: String.t(),
    email: String.t(),
    activated_at: DateTime.t(),
    fact_id: String.t(),
    fact_version: integer()
  }
  
  @doc """
  Creates a new account activated fact.
  """
  def new(account_id, email, activated_at \\ DateTime.utc_now()) do
    %__MODULE__{
      account_id: account_id,
      email: email,
      activated_at: activated_at,
      fact_id: UUID.uuid4(),
      fact_version: 1
    }
  end
end
```

### Fact Projection Pattern

Each domain has projections that convert domain events into facts and publish them:
```elixir
# lib/reckon_accounts/projections/account_facts_projection.ex
defmodule ReckonAccounts.Projections.AccountFactsProjection do
  @moduledoc """
  Projection that converts domain events into integration facts.
  
  Publishes facts to PubSub topics for consumption by other domains.
  """
  
  use Commanded.Projections.Ecto,
    application: ReckonAccounts.CommandedApp,
    repo: ReckonAccounts.Repo,
    name: "account_facts_projection"
  
  alias ReckonAccounts.VerifyEmail.Event, as: EmailVerifiedEvent
  alias ReckonShared.Accounts.AccountActivatedFact
  
  project(%EmailVerifiedEvent{} = event, _metadata) do
    # Convert domain event to integration fact
    fact = AccountActivatedFact.new(
      event.account_id,
      event.email,
      event.verified_at
    )
    
    # Publish to event-specific topic
    Phoenix.PubSub.publish(
      :ex_esdb_pubsub,
      "accounts:facts:account_activated",
      fact
    )
    
    :ok
  end
end
```

### Event-Specific Topics Communication

**Design Rule**: We communicate via event-specific topics, not generic domain topics.

**✅ GOOD - Event-specific topics:**
- `"accounts:facts:account_activated"`
- `"accounts:facts:account_closed"`
- `"profiles:facts:profile_created"`
- `"profiles:facts:profile_updated"`
- `"memberships:facts:membership_created"`

**❌ BAD - Generic domain topics:**
- `"accounts:events"`
- `"profiles:all"`
- `"domain:updates"`

### Cross-Domain Event Handling

Other domains subscribe to specific fact topics:
```elixir
# lib/reckon_profiles/event_handlers/account_event_handler.ex
defmodule ReckonProfiles.EventHandlers.AccountEventHandler do
  @moduledoc """
  Handles account-related facts from other domains.
  """
  
  use GenServer
  
  alias ReckonShared.Accounts.AccountActivatedFact
  alias ReckonProfiles.CreateProfile.Command
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Subscribe to specific account facts
    Phoenix.PubSub.subscribe(:ex_esdb_pubsub, "accounts:facts:account_activated")
    Phoenix.PubSub.subscribe(:ex_esdb_pubsub, "accounts:facts:account_closed")
    
    {:ok, %{}}
  end
  
  def handle_info(%AccountActivatedFact{} = fact, state) do
    # React to account activation by enabling profile creation
    # (Business logic here)
    {:noreply, state}
  end
end
```

### Topic Naming Convention

```
[source_domain]:facts:[event_name]
```

**Examples:**
- `accounts:facts:account_initialized`
- `accounts:facts:account_activated`
- `accounts:facts:account_closed`
- `profiles:facts:profile_created`
- `profiles:facts:profile_picture_updated`
- `memberships:facts:membership_created`
- `memberships:facts:membership_expired`

### Benefits of This Pattern

1. **Decoupling**: Domains don't know about each other, only about facts
2. **Versioning**: Facts can be versioned independently
3. **Selective Consumption**: Domains subscribe only to events they care about
4. **Auditability**: All integration events are explicitly defined as facts
5. **Testability**: Fact publishing and consumption can be tested independently

## Web UI Architecture

### Phoenix LiveView Preference

**Design Rule**: Use Phoenix LiveView instead of classic MVC architecture for interactive web interfaces.

**✅ PREFERRED - LiveView architecture:**
- Real-time interactivity without JavaScript
- Stateful user interfaces
- Server-side rendering with client-side updates
- Built-in handling of form validation and user feedback
- Simplified state management

**❌ AVOID - Classic MVC where LiveView is suitable:**
- Controllers for simple form handling
- Multiple request/response cycles for interactive features
- Client-side JavaScript for basic interactivity
- Complex form validation handling

### LiveView Module Structure

```elixir
# lib/landing_site_web/live/auth_live.ex
defmodule LandingSiteWeb.AuthLive do
  use LandingSiteWeb, :live_view
  
  # LiveView callbacks
  def mount(_params, _session, socket) do
    # Initialize socket state
  end
  
  def handle_event("register", %{"user" => user_params}, socket) do
    # Handle user registration
  end
  
  def handle_event("login", %{"user" => user_params}, socket) do
    # Handle user authentication
  end
  
  def render(assigns) do
    # Render the LiveView template
  end
end
```

### When to Use Classic MVC

**Acceptable use cases for Controllers:**
- API endpoints (JSON responses)
- Simple redirects or downloads
- Authentication callbacks (OAuth, etc.)
- Webhook handlers
- Static page rendering without interactivity

### Migration from MVC to LiveView

Refactoring from classic MVC to LiveView is generally straightforward:

1. **Controller actions** → **LiveView event handlers**
2. **Form submissions** → **LiveView events**
3. **Flash messages** → **LiveView assigns**
4. **Redirects** → **LiveView navigation**
5. **Template rendering** → **LiveView render function**

**Example migration:**
```elixir
# Before: Classic MVC
def create_account(conn, %{"user" => user_params}) do
  case UserContext.register_user(user_params) do
    {:ok, user} ->
      conn
      |> put_flash(:info, "Account created successfully")
      |> redirect(to: ~p"/auth/login")
    {:error, changeset} ->
      render(conn, :register, changeset: changeset)
  end
end

# After: LiveView
def handle_event("register", %{"user" => user_params}, socket) do
  case UserContext.register_user(user_params) do
    {:ok, user} ->
      socket
      |> put_flash(:info, "Account created successfully")
      |> push_navigate(to: ~p"/auth/login")
      |> noreply()
    {:error, changeset} ->
      socket
      |> assign(:changeset, changeset)
      |> noreply()
  end
end
```

## Reckon_App Integration Pattern

### DomainAPI Architecture

**Design Rule**: Each reckon_app owns a DomainAPI GenServer that provides the interface for external communication.

**Architecture Components:**

1. **DomainAPI GenServer**: Each reckon_app implements its own DomainAPI that:
   - Registers itself in Swarm using `Swarm.register_name(api_name(), self())`
   - Offers a user-friendly set of API functions for sending commands to the Domain
   - Handles `GenServer.cast` and `GenServer.call` callbacks
   - Uses pattern matching like `GenServer.cast(api_pid(), message)` to route messages

2. **Service Registration**: 
   ```elixir
   # In each reckon_app's DomainAPI
   defmodule ReckonProfiles.DomainAPI do
     use GenServer

     
     @domain_name :my_domain
     
     def api_name(), do: {:domain_api, @domain_name}
     def api_pid(), do: Swarm.whereis_name(api_name())
     
     def start_link(opts) do
       GenServer.start_link(__MODULE__, opts, name: __MODULE__)
     end
     
     def init(opts) do
       # Register this API with Swarm for discovery
       Swarm.register_name({:domain_api, :reckon_profiles}, __MODULE__, [])
       {:ok, opts}
     end
     
     # User-friendly API functions
     def establish_profile(account_id, display_name, bio \\ nil) do
       command = %ReckonProfiles.EstablishProfile.Command{
         account_id: account_id,
         display_name: display_name,
         bio: bio,
         requested_at: DateTime.utc_now()
       }
       
       GenServer.call(api_pid(), {:dispatch_command, command})
     end
     
     def handle_call({:dispatch_command, command}, _from, state) do
       result = ReckonProfiles.CommandedApp.dispatch(command)
       {:reply, result, state}
     end
   end
   ```

3. **Landing Site Integration**: 
   ```elixir
   # In landing_site mix.exs
   defp deps do
     [
       # Add each reckon_app as dependency without starting the application
       {:reckon_accounts, path: "../reckon_apps/reckon_accounts/", application: false},
       {:reckon_profiles, path: "../reckon_apps/reckon_profiles/", application: false},
       {:reckon_memberships, path: "../reckon_apps/reckon_memberships/", application: false}
     ]
   end
   ```

4. **LibCluster Configuration**: All services use the same cluster configuration to enable service discovery:
   ```elixir
   # In each reckon_app's config/config.exs
   config :libcluster,
     topologies: [
       reckon_cluster: [
         strategy: Cluster.Strategy.Gossip,
         config: [
           port: 45_890,  # Shared port for all reckon services
           if_addr: "0.0.0.0",
           multicast_addr: "230.1.1.251",
           multicast_ttl: 1,
           secret: System.get_env("RECKON_CLUSTER_SECRET") || "reckon_cluster_dev_secret"
         ]
       ]
     ]
   ```

### Benefits of This Pattern

1. **Domain Ownership**: Each reckon_app owns its API boundary and communication protocol
2. **Service Discovery**: Swarm provides automatic service discovery across the cluster
3. **Fault Tolerance**: Services can be started/stopped independently
4. **Clean Dependencies**: Landing site depends on reckon_apps for compilation but not runtime
5. **Scalability**: Multiple instances of each reckon_app can be deployed
6. **LibCluster Integration**: Follows the preferred clustering approach over seed_nodes

### Implementation Checklist

**For each reckon_app:**
- [ ] Implement DomainAPI GenServer with Swarm registration
- [ ] Add user-friendly API functions that wrap CommandedApp.dispatch calls
- [ ] Configure libcluster with shared cluster settings
- [ ] Add libcluster and swarm dependencies
- [ ] Update Application supervision tree to start DomainAPI

**For landing_site:**
- [ ] Add reckon_apps as `application: false` dependencies
- [ ] Implement service discovery to find available DomainAPIs
- [ ] Configure libcluster to join the same cluster
- [ ] Create communication layer that uses Swarm.whereis_name to find services

## Anti-Patterns to Avoid

1. **❌ Grouping by technical layer** (controllers/, services/, models/)
2. **❌ Shared command/event modules** (mixing multiple operations)
3. **❌ Generic naming** (using technical terms instead of business terms)
4. **❌ Horizontal slicing** (splitting one business operation across multiple technical layers)
5. **❌ Anemic domain models** (putting business logic in "service" classes)
6. **❌ Generic PubSub topics** (using broad topics instead of event-specific ones)
7. **❌ Direct domain coupling** (one domain importing modules from another)
8. **❌ Mixing domain events with integration facts** (using same struct for both)
9. **❌ CRUD-based event naming** (using generic -created, -updated, -deleted instead of meaningful business events)
10. **❌ Direct Router usage** (bypassing CommandedApp for command dispatch)
11. **❌ Multiple capabilities per module** (violating 1-capability-per-module rule)
12. **❌ Incorrect projection naming** (not following `<event>_to_<readmodel>.ex` format)
13. **❌ Policies bypassing CommandedApp** (direct command creation without proper dispatch)

### 🚫 FORBIDDEN: Direct Router Usage for Command Dispatch

**This anti-pattern is FORBIDDEN in all reckon_* applications.**

**❌ BAD - Direct Router usage:**
```elixir
defmodule ReckonProfiles do
  alias ReckonProfiles.Router  # 🚫 FORBIDDEN
  
  def create_profile(account_id, display_name, bio) do
    command = %ReckonProfiles.CreateProfile.Command{
      account_id: account_id,
      display_name: display_name,
      bio: bio,
      requested_at: DateTime.utc_now()
    }
    
    Router.dispatch(command)  # 🚫 FORBIDDEN - bypasses CommandedApp
  end
end
```

**✅ CORRECT - CommandedApp usage:**
```elixir
defmodule ReckonProfiles do
  alias ReckonProfiles.CommandedApp  # ✅ CORRECT
  
  def create_profile(account_id, display_name, bio) do
    command = %ReckonProfiles.CreateProfile.Command{
      account_id: account_id,
      display_name: display_name,
      bio: bio,
      requested_at: DateTime.utc_now()
    }
    
    CommandedApp.dispatch(command)  # ✅ CORRECT - goes through CommandedApp
  end
end
```

**Why this rule exists:**

1. **Architectural Consistency**: CommandedApp is the proper entry point for commands in Commanded
2. **Centralized Configuration**: CommandedApp handles event store config, middleware, and other application-level concerns
3. **Middleware Support**: CommandedApp can add middleware for logging, validation, authentication, etc.
4. **Error Handling**: Provides consistent error handling and retry logic across all commands
5. **Testing**: Easier to mock CommandedApp than individual router calls
6. **Future-Proofing**: Easier to add cross-cutting concerns like audit logging, metrics, etc.
7. **Commanded Best Practices**: `CommandedApp.dispatch()` is the idiomatic way in Commanded

**Command Flow:**
```
Business Logic (ReckonProfiles.ex)
         ↓
  CommandedApp.dispatch()  ✅ CORRECT
         ↓
    Router (internal routing)
         ↓
  Handler (processes command)
         ↓
    Events (domain events)
```

**NOT:**
```
Business Logic (ReckonProfiles.ex)
         ↓
    Router.dispatch()  🚫 FORBIDDEN
         ↓
  Handler (processes command)
         ↓
    Events (domain events)
```

**The Router is an internal implementation detail that should NEVER be called directly from business logic.**

### CRUD Events vs Business Events

**❌ BAD - CRUD-focused event names:**
- `ProfileCreated`
- `ProfileUpdated` 
- `ProfileDeleted`
- `AccountCreated`
- `AccountUpdated`
- `MembershipCreated`

**✅ GOOD - Business-focused event names:**
- `ProfileEstablished` (when user completes initial profile setup)
- `ProfilePersonalized` (when user customizes their profile)
- `ProfileDeactivated` (when user temporarily hides their profile)
- `AccountInitialized` (when registration begins)
- `AccountActivated` (when email is verified)
- `AccountSuspended` (when account is temporarily disabled)
- `AccountClosed` (when account is permanently closed)
- `TrialMembershipGranted` (when free trial begins)
- `PremiumMembershipUpgraded` (when user pays for premium)
- `MembershipExpired` (when subscription ends)

**Why this matters:**
- Business events capture **intent and meaning**, not just state changes
- They reflect the **ubiquitous language** of the domain
- They enable **better event sourcing** by preserving business context
- They make **event streams readable** as a business narrative
- They support **better analytics** and business intelligence
- They enable **temporal queries** that make business sense

**Example of business context preservation:**
```elixir
# ❌ BAD - Generic CRUD event
defmodule ReckonAccounts.AccountUpdated.Event do
  defstruct [:account_id, :changes, :updated_at]
end

# ✅ GOOD - Meaningful business events
defmodule ReckonAccounts.AccountActivated.Event do
  defstruct [:account_id, :email, :activated_at, :verification_token]
end

defmodule ReckonAccounts.AccountSuspended.Event do
  defstruct [:account_id, :reason, :suspended_at, :suspended_by]
end

defmodule ReckonAccounts.AccountClosed.Event do
  defstruct [:account_id, :reason, :closed_at, :requested_by]
end
```

Remember: The codebase should **scream** what it does, not how it's implemented!
