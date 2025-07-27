# ExESDB Subscription Health Management Proposal

## Overview

This proposal aims to extend the ExESDB system to receive and manage subscription health reports through the ExESDBGater API. The goal is to provide centralized health monitoring and management for subscriptions in the ExESDB ecosystem.

## Proposed Enhancements

### 1. Health Report Handling

Introduce new functions within the ExESDB server to process subscription health reports received through the ExESDBGater API.

- **Receive Health Reports**: Handle incoming health report messages.
- **Update Health Status**: Maintain current health status for each subscription.
- **Store Health Metrics**: Save performance metrics for analysis and alerting.

### 2. Health Data Storage

Leverage ETS or a persistent database to store health status and metrics for subscriptions.

- **ETS Tables**: For fast in-memory lookups and updates.
- **Backup Storage**: Periodic persistence to disk storage for durability.

### 3. Health Query Capabilities

Provide API endpoints to query the current health status, detailed metrics, and historical data for subscriptions.

- **Current Health Status**: Quick overview of subscription health.
- **Detailed Metrics**: In-depth analysis of subscription performance.
- **Historical Data**: Trends and patterns over time.

## API Proposal

### Health Report API

Extend the existing API to include functions to process and manage health reports sent by the ExESDBGater.

```elixir
@spec process_health_report(store :: atom(), report :: map()) :: :ok | {:error, term()}
def process_health_report(store, report)

@spec store_health_metric(store :: atom(), metrics :: map()) :: :ok | {:error, term()}
def store_health_metric(store, metrics)
```

### Health Query API

Develop endpoints to allow querying of health information.

```elixir
@spec query_health_status(store :: atom()) :: {:ok, map()} | {:error, term()}
def query_health_status(store)

@spec query_detailed_metrics(store :: atom(), subscription_name :: String.t()) :: {:ok, map()} | {:error, term()}
def query_detailed_metrics(store, subscription_name)
```

## Implementation Steps

1. **Integrate with ExESDBGater**: Enable health report processing.
2. **Design Health Storage**: Use ETS and fallback to persistent DB.
3. **Develop Health API**: Allow querying of health data.
4. **Testing**: Ensure robustness and performance under load.
5. **Documentation**: Provide comprehensive guides for integration.

## Next Steps

1. **Approval:** Validate this proposal aligns with system architecture.
2. **Task Breakdown:** Create actionable tasks for each component.
3. **Timeline:** Set a timeline for phased implementation.
4. **Review:** Iterate based on feedback and testing.

This enhancement aims to leverage the Gater API for real-time subscription health tracking, with centralized storage and retrieval, providing valuable insights and operational efficiency.
