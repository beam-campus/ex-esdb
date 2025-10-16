defmodule ExESDB.Telemetry do
  @moduledoc """
  Telemetry GenServer for the ExESDB core package.

  This module is responsible only for monitoring and observability within
  the core ex_esdb package. It follows proper separation of concerns by:

  1. Only handling telemetry events from this package
  2. Running as a supervised GenServer for reliability
  3. Broadcasting events through PubSub for external consumption
  4. Maintaining internal metrics and health state

  ## Responsibilities
  - Monitor event store read/write operations
  - Track stream operations and performance
  - Monitor subscription management and delivery
  - Track snapshot operations
  - Monitor gateway worker performance
  - Collect cluster consistency and health metrics

  ## Usage

  The telemetry server is automatically started by the ExESDB supervisor.
  To emit custom events from your code:

      ExESDB.Telemetry.emit(:stream_write_start, %{store: :my_store, stream: "my-stream"})
      ExESDB.Telemetry.emit(:stream_write_complete, %{store: :my_store, stream: "my-stream", events: 5, duration_us: 1500})

  To get current metrics:

      ExESDB.Telemetry.get_metrics()
      ExESDB.Telemetry.get_health()
  """

  use GenServer
  require Logger
  alias Phoenix.PubSub

  @pubsub_server :ex_esdb_metrics

  # Telemetry events this module handles
  @telemetry_events [
    [:ex_esdb, :stream, :write, :start],
    [:ex_esdb, :stream, :write, :stop],
    [:ex_esdb, :stream, :write, :error],
    [:ex_esdb, :stream, :read, :start],
    [:ex_esdb, :stream, :read, :stop],
    [:ex_esdb, :stream, :read, :error],
    [:ex_esdb, :subscription, :created],
    [:ex_esdb, :subscription, :event_delivered],
    [:ex_esdb, :subscription, :error],
    [:ex_esdb, :snapshot, :write, :start],
    [:ex_esdb, :snapshot, :write, :stop],
    [:ex_esdb, :snapshot, :read, :start],
    [:ex_esdb, :snapshot, :read, :stop],
    [:ex_esdb, :gateway_worker, :call, :start],
    [:ex_esdb, :gateway_worker, :call, :stop],
    [:ex_esdb, :consistency, :check, :start],
    [:ex_esdb, :consistency, :check, :stop],
    [:ex_esdb, :cluster, :node, :join],
    [:ex_esdb, :cluster, :node, :leave]
  ]

  # Metrics collection interval (30 seconds)
  @metrics_interval 30_000

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc """
  Emit a telemetry event from application code.
  """
  def emit(event_name, metadata \\ %{}) when is_atom(event_name) do
    measurements = %{
      timestamp: System.monotonic_time(:microsecond),
      system_time: System.system_time(:microsecond)
    }

    :telemetry.execute([:ex_esdb, event_name], measurements, metadata)
  end

  @doc """
  Get current metrics summary.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Get current health status.
  """
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @doc """
  Reset metrics counters.
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    # Attach telemetry handlers
    :telemetry.attach_many(
      "ex-esdb-telemetry",
      @telemetry_events,
      &handle_telemetry_event/4,
      %{}
    )

    # Schedule periodic metrics collection
    Process.send_after(self(), :collect_metrics, @metrics_interval)

    initial_state = %{
      # Stream operations
      streams: %{
        writes: %{total: 0, errors: 0, avg_duration_us: 0, events_written: 0},
        reads: %{total: 0, errors: 0, avg_duration_us: 0, events_read: 0},
        by_store: %{}
      },

      # Subscription metrics
      subscriptions: %{
        active: 0,
        created: 0,
        events_delivered: 0,
        errors: 0,
        by_store: %{}
      },

      # Snapshot operations
      snapshots: %{
        writes: %{total: 0, avg_duration_us: 0},
        reads: %{total: 0, avg_duration_us: 0},
        by_store: %{}
      },

      # Gateway worker metrics
      gateway_workers: %{
        calls: %{total: 0, errors: 0, avg_duration_us: 0},
        by_operation: %{}
      },

      # Consistency checks
      consistency: %{
        checks: %{total: 0, passed: 0, failed: 0, avg_duration_us: 0},
        last_check: nil
      },

      # Cluster metrics
      cluster: %{
        nodes: %{joined: 0, left: 0, current: []},
        topology_changes: 0
      },

      # System metrics
      system_metrics: %{},
      last_metrics_collection: DateTime.utc_now(),

      # Configuration
      config: Map.new(opts)
    }

    Logger.info("ExESDB.Telemetry started successfully")
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      streams: state.streams,
      subscriptions: state.subscriptions,
      snapshots: state.snapshots,
      gateway_workers: state.gateway_workers,
      consistency: state.consistency,
      cluster: state.cluster,
      system_metrics: state.system_metrics,
      last_updated: state.last_metrics_collection
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    health = %{
      status: calculate_overall_health(state),
      stream_health: calculate_stream_health(state),
      subscription_health: calculate_subscription_health(state),
      consistency_health: calculate_consistency_health(state),
      cluster_health: calculate_cluster_health(state),
      node: Node.self(),
      timestamp: DateTime.utc_now()
    }

    {:reply, health, state}
  end

  @impl true
  def handle_call(:reset_metrics, _from, state) do
    reset_state = %{
      state
      | streams: %{
          writes: %{total: 0, errors: 0, avg_duration_us: 0, events_written: 0},
          reads: %{total: 0, errors: 0, avg_duration_us: 0, events_read: 0},
          by_store: %{}
        },
        subscriptions: %{active: 0, created: 0, events_delivered: 0, errors: 0, by_store: %{}},
        snapshots: %{
          writes: %{total: 0, avg_duration_us: 0},
          reads: %{total: 0, avg_duration_us: 0},
          by_store: %{}
        },
        gateway_workers: %{calls: %{total: 0, errors: 0, avg_duration_us: 0}, by_operation: %{}},
        consistency: %{
          checks: %{total: 0, passed: 0, failed: 0, avg_duration_us: 0},
          last_check: nil
        }
    }

    {:reply, :ok, reset_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect system metrics
    system_metrics = collect_system_metrics()

    # Broadcast current state
    broadcast_metrics_update(state, system_metrics)

    # Schedule next collection
    Process.send_after(self(), :collect_metrics, @metrics_interval)

    updated_state = %{
      state
      | system_metrics: system_metrics,
        last_metrics_collection: DateTime.utc_now()
    }

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    updated_state = process_telemetry_event(event, measurements, metadata, state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("ExESDB.Telemetry received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    # Detach telemetry handlers
    :telemetry.detach("ex-esdb-telemetry")
    Logger.info("ExESDB.Telemetry terminated: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  # Telemetry event handler (runs in caller's process)
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    # Send to GenServer for processing (non-blocking)
    send(__MODULE__, {:telemetry_event, event, measurements, metadata})
  end

  ## Pattern-matched telemetry event processors

  # Stream write events
  defp process_telemetry_event(
         [:ex_esdb, :stream, :write, :start],
         _measurements,
         metadata,
         state
       ) do
    store = Map.get(metadata, :store, :unknown)

    updated_streams =
      update_in(state.streams.by_store, [store], fn store_metrics ->
        Map.update(store_metrics || %{}, :write_starts, 1, &(&1 + 1))
      end)

    %{state | streams: updated_streams}
  end

  defp process_telemetry_event([:ex_esdb, :stream, :write, :stop], measurements, metadata, state) do
    duration_us = Map.get(measurements, :duration, 0)
    events_count = Map.get(metadata, :events_count, 1)
    _store = Map.get(metadata, :store, :unknown)

    current_writes = state.streams.writes
    new_total = current_writes.total + 1
    new_events = current_writes.events_written + events_count

    # Calculate new average duration
    current_avg = current_writes.avg_duration_us

    new_avg =
      if new_total > 1 do
        (current_avg * (new_total - 1) + duration_us) / new_total
      else
        duration_us
      end

    updated_writes = %{
      current_writes
      | total: new_total,
        avg_duration_us: new_avg,
        events_written: new_events
    }

    updated_streams = %{state.streams | writes: updated_writes}

    # Check for performance issues
    # > 10 seconds
    if duration_us > 10_000_000 do
      broadcast_performance_alert(:slow_stream_write, metadata, duration_us)
    end

    %{state | streams: updated_streams}
  end

  defp process_telemetry_event(
         [:ex_esdb, :stream, :write, :error],
         _measurements,
         metadata,
         state
       ) do
    updated_writes = %{state.streams.writes | errors: state.streams.writes.errors + 1}

    updated_streams = %{state.streams | writes: updated_writes}

    broadcast_performance_alert(:stream_write_error, metadata, nil)

    %{state | streams: updated_streams}
  end

  # Stream read events
  defp process_telemetry_event(
         [:ex_esdb, :stream, :read, :start],
         _measurements,
         _metadata,
         state
       ) do
    state
  end

  defp process_telemetry_event([:ex_esdb, :stream, :read, :stop], measurements, metadata, state) do
    duration_us = Map.get(measurements, :duration, 0)
    events_count = Map.get(metadata, :events_count, 0)

    current_reads = state.streams.reads
    new_total = current_reads.total + 1
    new_events = current_reads.events_read + events_count

    # Calculate new average duration
    current_avg = current_reads.avg_duration_us

    new_avg =
      if new_total > 1 do
        (current_avg * (new_total - 1) + duration_us) / new_total
      else
        duration_us
      end

    updated_reads = %{
      current_reads
      | total: new_total,
        avg_duration_us: new_avg,
        events_read: new_events
    }

    updated_streams = %{state.streams | reads: updated_reads}

    %{state | streams: updated_streams}
  end

  defp process_telemetry_event([:ex_esdb, :stream, :read, :error], _measurements, metadata, state) do
    updated_reads = %{state.streams.reads | errors: state.streams.reads.errors + 1}

    updated_streams = %{state.streams | reads: updated_reads}

    broadcast_performance_alert(:stream_read_error, metadata, nil)

    %{state | streams: updated_streams}
  end

  # Subscription events
  defp process_telemetry_event(
         [:ex_esdb, :subscription, :created],
         _measurements,
         metadata,
         state
       ) do
    store = Map.get(metadata, :store, :unknown)

    updated_subscriptions = %{
      state.subscriptions
      | active: state.subscriptions.active + 1,
        created: state.subscriptions.created + 1,
        by_store: Map.update(state.subscriptions.by_store, store, 1, &(&1 + 1))
    }

    %{state | subscriptions: updated_subscriptions}
  end

  defp process_telemetry_event(
         [:ex_esdb, :subscription, :event_delivered],
         _measurements,
         _metadata,
         state
       ) do
    updated_subscriptions = %{
      state.subscriptions
      | events_delivered: state.subscriptions.events_delivered + 1
    }

    %{state | subscriptions: updated_subscriptions}
  end

  defp process_telemetry_event([:ex_esdb, :subscription, :error], _measurements, metadata, state) do
    updated_subscriptions = %{state.subscriptions | errors: state.subscriptions.errors + 1}

    broadcast_performance_alert(:subscription_error, metadata, nil)

    %{state | subscriptions: updated_subscriptions}
  end

  # Snapshot events
  defp process_telemetry_event(
         [:ex_esdb, :snapshot, :write, :start],
         _measurements,
         _metadata,
         state
       ) do
    state
  end

  defp process_telemetry_event(
         [:ex_esdb, :snapshot, :write, :stop],
         measurements,
         _metadata,
         state
       ) do
    duration_us = Map.get(measurements, :duration, 0)

    current_writes = state.snapshots.writes
    new_total = current_writes.total + 1

    current_avg = current_writes.avg_duration_us

    new_avg =
      if new_total > 1 do
        (current_avg * (new_total - 1) + duration_us) / new_total
      else
        duration_us
      end

    updated_writes = %{current_writes | total: new_total, avg_duration_us: new_avg}

    updated_snapshots = %{state.snapshots | writes: updated_writes}

    %{state | snapshots: updated_snapshots}
  end

  defp process_telemetry_event(
         [:ex_esdb, :snapshot, :read, :start],
         _measurements,
         _metadata,
         state
       ) do
    state
  end

  defp process_telemetry_event(
         [:ex_esdb, :snapshot, :read, :stop],
         measurements,
         _metadata,
         state
       ) do
    duration_us = Map.get(measurements, :duration, 0)

    current_reads = state.snapshots.reads
    new_total = current_reads.total + 1

    current_avg = current_reads.avg_duration_us

    new_avg =
      if new_total > 1 do
        (current_avg * (new_total - 1) + duration_us) / new_total
      else
        duration_us
      end

    updated_reads = %{current_reads | total: new_total, avg_duration_us: new_avg}

    updated_snapshots = %{state.snapshots | reads: updated_reads}

    %{state | snapshots: updated_snapshots}
  end

  # Gateway worker events
  defp process_telemetry_event(
         [:ex_esdb, :gateway_worker, :call, :start],
         _measurements,
         _metadata,
         state
       ) do
    state
  end

  defp process_telemetry_event(
         [:ex_esdb, :gateway_worker, :call, :stop],
         measurements,
         metadata,
         state
       ) do
    duration_us = Map.get(measurements, :duration, 0)
    operation = Map.get(metadata, :operation, :unknown)

    current_calls = state.gateway_workers.calls
    new_total = current_calls.total + 1

    current_avg = current_calls.avg_duration_us

    new_avg =
      if new_total > 1 do
        (current_avg * (new_total - 1) + duration_us) / new_total
      else
        duration_us
      end

    updated_calls = %{current_calls | total: new_total, avg_duration_us: new_avg}

    updated_workers = %{
      state.gateway_workers
      | calls: updated_calls,
        by_operation: Map.update(state.gateway_workers.by_operation, operation, 1, &(&1 + 1))
    }

    %{state | gateway_workers: updated_workers}
  end

  # Consistency check events
  defp process_telemetry_event(
         [:ex_esdb, :consistency, :check, :start],
         _measurements,
         _metadata,
         state
       ) do
    state
  end

  defp process_telemetry_event(
         [:ex_esdb, :consistency, :check, :stop],
         measurements,
         metadata,
         state
       ) do
    duration_us = Map.get(measurements, :duration, 0)
    result = Map.get(metadata, :result, :unknown)

    current_checks = state.consistency.checks
    new_total = current_checks.total + 1
    new_passed = if result == :passed, do: current_checks.passed + 1, else: current_checks.passed
    new_failed = if result == :failed, do: current_checks.failed + 1, else: current_checks.failed

    current_avg = current_checks.avg_duration_us

    new_avg =
      if new_total > 1 do
        (current_avg * (new_total - 1) + duration_us) / new_total
      else
        duration_us
      end

    updated_checks = %{
      current_checks
      | total: new_total,
        passed: new_passed,
        failed: new_failed,
        avg_duration_us: new_avg
    }

    updated_consistency = %{
      state.consistency
      | checks: updated_checks,
        last_check: DateTime.utc_now()
    }

    %{state | consistency: updated_consistency}
  end

  # Cluster events
  defp process_telemetry_event([:ex_esdb, :cluster, :node, :join], _measurements, metadata, state) do
    node = Map.get(metadata, :node)

    updated_nodes = %{
      state.cluster.nodes
      | joined: state.cluster.nodes.joined + 1,
        current: [node | state.cluster.nodes.current] |> Enum.uniq()
    }

    updated_cluster = %{
      state.cluster
      | nodes: updated_nodes,
        topology_changes: state.cluster.topology_changes + 1
    }

    broadcast_cluster_event(:node_join, metadata)

    %{state | cluster: updated_cluster}
  end

  defp process_telemetry_event(
         [:ex_esdb, :cluster, :node, :leave],
         _measurements,
         metadata,
         state
       ) do
    node = Map.get(metadata, :node)

    updated_nodes = %{
      state.cluster.nodes
      | left: state.cluster.nodes.left + 1,
        current: List.delete(state.cluster.nodes.current, node)
    }

    updated_cluster = %{
      state.cluster
      | nodes: updated_nodes,
        topology_changes: state.cluster.topology_changes + 1
    }

    broadcast_cluster_event(:node_leave, metadata)

    %{state | cluster: updated_cluster}
  end

  # Catch-all for unknown events
  defp process_telemetry_event(event, _measurements, _metadata, state) do
    Logger.debug("Unknown telemetry event: #{inspect(event)}")
    state
  end

  ## Helper Functions

  # System metrics collection
  defp collect_system_metrics do
    %{
      memory: :erlang.memory(),
      process_count: length(Process.list()),
      connected_nodes: Node.list(),
      uptime_ms: :erlang.statistics(:uptime) |> elem(0),
      schedulers: :erlang.system_info(:schedulers),
      timestamp: DateTime.utc_now()
    }
  rescue
    _ -> %{error: "Failed to collect system metrics", timestamp: DateTime.utc_now()}
  end

  ## Health Calculations

  defp calculate_overall_health(state) do
    stream_healthy = calculate_stream_health(state) in [:healthy, :degraded]
    subscription_healthy = calculate_subscription_health(state) in [:healthy, :degraded]
    consistency_healthy = calculate_consistency_health(state) in [:healthy, :degraded]

    cond do
      stream_healthy and subscription_healthy and consistency_healthy -> :healthy
      stream_healthy and subscription_healthy -> :degraded
      true -> :unhealthy
    end
  end

  defp calculate_stream_health(state) do
    write_error_rate =
      if state.streams.writes.total > 0 do
        state.streams.writes.errors / state.streams.writes.total
      else
        0.0
      end

    read_error_rate =
      if state.streams.reads.total > 0 do
        state.streams.reads.errors / state.streams.reads.total
      else
        0.0
      end

    avg_write_duration_ms = state.streams.writes.avg_duration_us / 1000

    cond do
      write_error_rate < 0.01 and read_error_rate < 0.01 and avg_write_duration_ms < 5000 ->
        :healthy

      write_error_rate < 0.05 and read_error_rate < 0.05 and avg_write_duration_ms < 15000 ->
        :degraded

      true ->
        :unhealthy
    end
  end

  defp calculate_subscription_health(state) do
    error_rate =
      if state.subscriptions.events_delivered > 0 do
        state.subscriptions.errors / state.subscriptions.events_delivered
      else
        0.0
      end

    cond do
      error_rate < 0.01 -> :healthy
      error_rate < 0.05 -> :degraded
      true -> :unhealthy
    end
  end

  defp calculate_consistency_health(state) do
    if state.consistency.checks.total > 0 do
      success_rate = state.consistency.checks.passed / state.consistency.checks.total

      cond do
        success_rate > 0.95 -> :healthy
        success_rate > 0.80 -> :degraded
        true -> :unhealthy
      end
    else
      :unknown
    end
  end

  defp calculate_cluster_health(state) do
    current_nodes = length(state.cluster.nodes.current)

    cond do
      current_nodes >= 3 -> :healthy
      current_nodes >= 1 -> :degraded
      true -> :unhealthy
    end
  end

  ## Broadcasting Functions

  defp broadcast_metrics_update(state, system_metrics) do
    message = %{
      type: :metrics_update,
      package: :ex_esdb,
      node: Node.self(),
      metrics: %{
        streams: state.streams,
        subscriptions: state.subscriptions,
        snapshots: state.snapshots,
        gateway_workers: state.gateway_workers,
        consistency: state.consistency,
        cluster: state.cluster,
        system: system_metrics
      },
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(@pubsub_server, "esdb:metrics", {:metrics_update, message})
  end

  defp broadcast_performance_alert(alert_type, metadata, duration) do
    alert = %{
      type: :performance_alert,
      alert: alert_type,
      package: :ex_esdb,
      node: Node.self(),
      duration_us: duration,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(@pubsub_server, "esdb:alerts", {:performance_alert, alert})
  end

  defp broadcast_cluster_event(event_type, metadata) do
    event = %{
      type: :cluster_event,
      event: event_type,
      package: :ex_esdb,
      node: Node.self(),
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(@pubsub_server, "esdb:cluster", {:cluster_event, event})
  end
end
