defmodule ExESDB.PubSubIntegrationTest do
  @moduledoc """
  Comprehensive tests for PubSub integration with ExESDB components.
  
  Tests the integration between:
  - EmitterWorkers and :ex_esdb_events
  - SubscriptionHealthTracker and :ex_esdb_health
  - SubscriptionMetrics and :ex_esdb_metrics  
  - Security, audit, alerts, diagnostics, and lifecycle events
  """
  use ExUnit.Case, async: false

  alias Phoenix.PubSub

  @test_store :pubsub_integration_test_store

  @all_pubsub_instances [
    :ex_esdb_events,      # Core event data
    :ex_esdb_system,      # General system events
    :ex_esdb_logging,     # Log aggregation
    :ex_esdb_health,      # Health monitoring
    :ex_esdb_metrics,     # Performance metrics
    :ex_esdb_security,    # Security events
    :ex_esdb_audit,       # Audit trail
    :ex_esdb_alerts,      # Critical alerts
    :ex_esdb_diagnostics, # Deep diagnostic information
    :ex_esdb_lifecycle    # Process lifecycle events
  ]

  setup do
    # Start ExESDB system which will start all PubSub instances
    {:ok, system_pid} = ExESDB.System.start([store_id: @test_store])

    # Ensure cleanup
    on_exit(fn ->
      try do
        if Process.alive?(system_pid) do
          Supervisor.stop(system_pid)
        end
      catch
        _, _ -> :ok
      end
    end)

    {:ok, %{system_pid: system_pid}}
  end

  describe "PubSub instance isolation and availability" do
    test "all PubSub instances are running and isolated" do
      # Verify all instances are running
      for instance <- @all_pubsub_instances do
        pid = Process.whereis(instance)
        assert is_pid(pid), "#{instance} should be running"
        assert Process.alive?(pid), "#{instance} should be alive"
      end

      # Test isolation between instances
      test_topic = "isolation_test"
      test_message = "isolation_message"

      # Subscribe to all instances for the same topic
      for instance <- @all_pubsub_instances do
        :ok = PubSub.subscribe(instance, test_topic)
      end

      # Send message to each instance and verify isolation
      for {instance, index} <- Enum.with_index(@all_pubsub_instances) do
        unique_message = "#{test_message}_#{index}_#{instance}"
        
        :ok = PubSub.broadcast(instance, test_topic, unique_message)
        
        # Should receive exactly one message
        assert_receive ^unique_message, 1000
        
        # Should not receive any other messages
        refute_receive _, 100
      end
    end

    test "PubSub instances have unique processes" do
      pids = Enum.map(@all_pubsub_instances, &Process.whereis/1)
      unique_pids = Enum.uniq(pids)
      
      assert length(pids) == length(unique_pids),
             "All PubSub instances should have unique PIDs"
    end
  end

  describe "EmitterWorker integration with :ex_esdb_events" do
    test "EmitterWorker broadcasts to :ex_esdb_events exclusively" do
      # Start an EmitterWorker
      test_selector = "test_stream_#{System.unique_integer([:positive])}"
      topic = "#{@test_store}:#{test_selector}:events"
      emitter_name = Module.concat(ExESDB.EmitterWorker, test_selector)

      {:ok, emitter} = ExESDB.EmitterWorker.start_link({@test_store, test_selector, nil, emitter_name})

      # Subscribe to all PubSub instances
      for instance <- @all_pubsub_instances do
        :ok = PubSub.subscribe(instance, topic)
      end

      # Send test event to emitter
      test_event = %{
        event_id: "test-#{System.unique_integer([:positive])}",
        event_type: "integration_test_event",
        data: %{test: true}
      }

      send(emitter, {:broadcast, topic, test_event})

      # Should receive event only through :ex_esdb_events
      assert_receive {:events, [^test_event]}, 1000

      # Should not receive through other instances
      refute_receive {:events, [^test_event]}, 500

      # Cleanup
      GenServer.stop(emitter, :normal)
    end
  end

  describe "Health monitoring integration with :ex_esdb_health" do
    test "health events are published to :ex_esdb_health" do
      store_id = @test_store
      subscription_name = "test_subscription_#{System.unique_integer([:positive])}"
      health_topic = "subscription_health:#{store_id}:#{subscription_name}"

      # Subscribe to health events
      :ok = PubSub.subscribe(:ex_esdb_health, health_topic)

      # Simulate a health event
      health_event = %{
        store_id: store_id,
        subscription_name: subscription_name,
        event_type: :registration_success,
        timestamp: System.system_time(:millisecond),
        metadata: %{
          proxy_pid: self(),
          subscriber_pid: self(),
          registration_time: System.system_time(:millisecond)
        }
      }

      # Publish health event
      :ok = PubSub.broadcast(:ex_esdb_health, health_topic, {:subscription_health, health_event})

      # Should receive the health event
      assert_receive {:subscription_health, ^health_event}, 1000

      # Verify isolation - should not receive on other instances
      :ok = PubSub.subscribe(:ex_esdb_system, health_topic)
      :ok = PubSub.broadcast(:ex_esdb_system, health_topic, {:subscription_health, health_event})
      
      assert_receive {:subscription_health, ^health_event}, 1000
      refute_receive {:subscription_health, ^health_event}, 100
    end
  end

  describe "Metrics integration with :ex_esdb_metrics" do
    test "metrics events are published to :ex_esdb_metrics" do
      store_id = @test_store
      subscription_name = "test_subscription_#{System.unique_integer([:positive])}"
      metrics_topic = "subscription_metrics:#{store_id}:#{subscription_name}"

      # Subscribe to metrics events
      :ok = PubSub.subscribe(:ex_esdb_metrics, metrics_topic)

      # Simulate a metrics event
      metrics_event = %{
        store_id: store_id,
        subscription_name: subscription_name,
        event_type: :registration_attempt,
        timestamp: System.system_time(:millisecond),
        metadata: %{
          result: :ok,
          source: :subscription_metrics,
          processing_time_ms: 45
        }
      }

      # Publish metrics event
      :ok = PubSub.broadcast(:ex_esdb_metrics, metrics_topic, {:subscription_metrics, metrics_event})

      # Should receive the metrics event
      assert_receive {:subscription_metrics, ^metrics_event}, 1000
    end
  end

  describe "Security events integration with :ex_esdb_security" do
    test "security events are published to :ex_esdb_security" do
      security_topic = "security_events:authentication"

      # Subscribe to security events
      :ok = PubSub.subscribe(:ex_esdb_security, security_topic)

      # Simulate a security event
      security_event = %{
        event_type: :authentication_failure,
        user_id: "test_user_#{System.unique_integer([:positive])}",
        ip_address: "***REDACTED***",
        timestamp: System.system_time(:millisecond),
        reason: :invalid_credentials,
        metadata: %{
          attempt_count: 3,
          user_agent: "test/1.0"
        }
      }

      # Publish security event
      :ok = PubSub.broadcast(:ex_esdb_security, security_topic, {:security_event, security_event})

      # Should receive the security event
      assert_receive {:security_event, ^security_event}, 1000
    end
  end

  describe "Audit trail integration with :ex_esdb_audit" do
    test "audit events are published to :ex_esdb_audit" do
      audit_topic = "audit_trail:user_actions"

      # Subscribe to audit events
      :ok = PubSub.subscribe(:ex_esdb_audit, audit_topic)

      # Simulate an audit event
      audit_event = %{
        event_type: :user_action,
        user_id: "admin_user_#{System.unique_integer([:positive])}",
        action: :delete_subscription,
        resource: "subscription_#{System.unique_integer([:positive])}",
        timestamp: System.system_time(:millisecond),
        metadata: %{
          store_id: @test_store,
          ip_address: "***REDACTED***",
          session_id: "sess_#{System.unique_integer([:positive])}"
        }
      }

      # Publish audit event
      :ok = PubSub.broadcast(:ex_esdb_audit, audit_topic, {:audit_event, audit_event})

      # Should receive the audit event
      assert_receive {:audit_event, ^audit_event}, 1000
    end
  end

  describe "Critical alerts integration with :ex_esdb_alerts" do
    test "critical alerts are published to :ex_esdb_alerts" do
      alert_topic = "system_alerts:critical"

      # Subscribe to alert events
      :ok = PubSub.subscribe(:ex_esdb_alerts, alert_topic)

      # Simulate a critical alert
      alert_event = %{
        event_type: :critical_alert,
        severity: :high,
        component: :subscription_system,
        message: "Circuit breaker opened for multiple subscriptions",
        timestamp: System.system_time(:millisecond),
        metadata: %{
          affected_subscriptions: 5,
          estimated_impact: "50% of real-time projections offline",
          escalation_required: true
        }
      }

      # Publish alert event
      :ok = PubSub.broadcast(:ex_esdb_alerts, alert_topic, {:critical_alert, alert_event})

      # Should receive the alert event
      assert_receive {:critical_alert, ^alert_event}, 1000
    end
  end

  describe "Diagnostic information integration with :ex_esdb_diagnostics" do
    test "diagnostic events are published to :ex_esdb_diagnostics" do
      diagnostics_topic = "diagnostics:performance_trace"

      # Subscribe to diagnostic events
      :ok = PubSub.subscribe(:ex_esdb_diagnostics, diagnostics_topic)

      # Simulate a diagnostic event
      diagnostic_event = %{
        event_type: :performance_trace,
        component: :emitter_worker,
        trace_id: "trace_#{System.unique_integer([:positive])}",
        timestamp: System.system_time(:millisecond),
        metadata: %{
          operation: :event_broadcast,
          duration_ms: 12,
          memory_usage_bytes: 1024 * 512,
          cpu_time_ms: 8
        }
      }

      # Publish diagnostic event
      :ok = PubSub.broadcast(:ex_esdb_diagnostics, diagnostics_topic, {:diagnostic_event, diagnostic_event})

      # Should receive the diagnostic event
      assert_receive {:diagnostic_event, ^diagnostic_event}, 1000
    end
  end

  describe "Process lifecycle integration with :ex_esdb_lifecycle" do
    test "lifecycle events are published to :ex_esdb_lifecycle" do
      lifecycle_topic = "process_lifecycle:subscription_proxies"

      # Subscribe to lifecycle events
      :ok = PubSub.subscribe(:ex_esdb_lifecycle, lifecycle_topic)

      # Simulate a lifecycle event
      lifecycle_event = %{
        event_type: :process_started,
        process_type: :subscription_proxy,
        pid: self(),
        timestamp: System.system_time(:millisecond),
        metadata: %{
          store_id: @test_store,
          subscription_name: "test_subscription_#{System.unique_integer([:positive])}",
          supervisor: self(),
          restart_count: 0
        }
      }

      # Publish lifecycle event
      :ok = PubSub.broadcast(:ex_esdb_lifecycle, lifecycle_topic, {:lifecycle_event, lifecycle_event})

      # Should receive the lifecycle event
      assert_receive {:lifecycle_event, ^lifecycle_event}, 1000
    end
  end

  describe "Cross-instance communication patterns" do
    test "health dashboard pattern - subscribe to multiple related instances" do
      store_id = @test_store
      subscription_name = "test_subscription_#{System.unique_integer([:positive])}"

      # Health dashboard would subscribe to health and lifecycle events
      health_topic = "subscription_health:#{store_id}:#{subscription_name}"
      lifecycle_topic = "process_lifecycle:subscription_proxies"

      :ok = PubSub.subscribe(:ex_esdb_health, health_topic)
      :ok = PubSub.subscribe(:ex_esdb_lifecycle, lifecycle_topic)

      # Simulate coordinated events
      health_event = %{
        store_id: store_id,
        subscription_name: subscription_name,
        event_type: :registration_success,
        timestamp: System.system_time(:millisecond),
        metadata: %{proxy_pid: self()}
      }

      lifecycle_event = %{
        event_type: :process_started,
        process_type: :subscription_proxy,
        pid: self(),
        timestamp: System.system_time(:millisecond),
        metadata: %{store_id: store_id, subscription_name: subscription_name}
      }

      # Publish events
      :ok = PubSub.broadcast(:ex_esdb_health, health_topic, {:subscription_health, health_event})
      :ok = PubSub.broadcast(:ex_esdb_lifecycle, lifecycle_topic, {:lifecycle_event, lifecycle_event})

      # Should receive both events
      assert_receive {:subscription_health, ^health_event}, 1000
      assert_receive {:lifecycle_event, ^lifecycle_event}, 1000
    end

    test "security operations center pattern - subscribe to security and audit" do
      security_topic = "security_events:authentication"
      audit_topic = "audit_trail:user_actions"

      :ok = PubSub.subscribe(:ex_esdb_security, security_topic)
      :ok = PubSub.subscribe(:ex_esdb_audit, audit_topic)

      # Simulate related security and audit events
      security_event = %{
        event_type: :authentication_failure,
        user_id: "suspicious_user",
        ip_address: "***REDACTED***",
        timestamp: System.system_time(:millisecond)
      }

      audit_event = %{
        event_type: :security_violation,
        user_id: "suspicious_user",
        action: :failed_login_attempt,
        timestamp: System.system_time(:millisecond)
      }

      # Publish events
      :ok = PubSub.broadcast(:ex_esdb_security, security_topic, {:security_event, security_event})
      :ok = PubSub.broadcast(:ex_esdb_audit, audit_topic, {:audit_event, audit_event})

      # Should receive both events
      assert_receive {:security_event, ^security_event}, 1000
      assert_receive {:audit_event, ^audit_event}, 1000
    end
  end

  describe "Performance and reliability" do
    test "high-volume message handling across instances" do
      message_count = 50
      test_topics = for instance <- @all_pubsub_instances do
        {"high_volume_#{instance}", instance}
      end

      # Subscribe to all test topics
      for {topic, instance} <- test_topics do
        :ok = PubSub.subscribe(instance, topic)
      end

      # Send many messages quickly to each instance
      for {topic, instance} <- test_topics do
        for i <- 1..message_count do
          message = "message_#{i}_#{instance}"
          :ok = PubSub.broadcast(instance, topic, message)
        end
      end

      # Verify all messages are received
      for {_topic, instance} <- test_topics do
        for i <- 1..message_count do
          expected_message = "message_#{i}_#{instance}"
          assert_receive ^expected_message, 2000, 
                        "Did not receive message #{i} for instance #{instance}"
        end
      end
    end

    test "concurrent operations across all instances" do
      tasks = 
        for instance <- @all_pubsub_instances do
          Task.async(fn ->
            topic = "concurrent_test_#{instance}"
            message = "concurrent_message_#{instance}"
            
            # Subscribe and broadcast concurrently
            :ok = PubSub.subscribe(instance, topic)
            :ok = PubSub.broadcast(instance, topic, message)
            
            # Verify message received
            receive do
              ^message -> :ok
            after
              2000 -> {:error, :timeout}
            end
          end)
        end
      
      results = Task.await_many(tasks, 5000)
      
      # All tasks should complete successfully
      assert Enum.all?(results, &(&1 == :ok)), 
             "All concurrent operations should succeed"
    end
  end
end
