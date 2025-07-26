defmodule ExESDB.PubSubDependencyTest do
  use ExUnit.Case, async: false

  alias Phoenix.PubSub

  @pubsub_instances [:ex_esdb_events, :ex_esdb_system, :ex_esdb_logging]

  describe "System startup with integrated PubSub" do
    test "automatically starts PubSub instances" do
      # Start ExESDB.System which should start PubSub internally
      system_pid = ExESDB.System.start([store_id: :pubsub_dep_test_1])
      assert is_pid(system_pid)
      assert Process.alive?(system_pid)

      # Verify all PubSub instances are running
      for name <- @pubsub_instances do
        pid = Process.whereis(name)
        assert is_pid(pid), "Expected #{name} to be running"
        assert Process.alive?(pid), "Expected #{name} to be alive"
      end

      # Clean up
      Supervisor.stop(system_pid)
    end

    test "PubSub instances are functional after system start" do
      # Start the system
      system_pid = ExESDB.System.start([store_id: :pubsub_dep_test_2])
      assert is_pid(system_pid)

      # Test PubSub functionality
      test_topic = "test_topic"
      test_message = "test_message"

      # Subscribe to each instance
      for name <- @pubsub_instances do
        :ok = PubSub.subscribe(name, test_topic)
      end

      # Broadcast to each instance
      for name <- @pubsub_instances do
        :ok = PubSub.broadcast(name, test_topic, test_message)
        # Should receive one message per instance
        assert_receive ^test_message
      end

      # Clean up
      Supervisor.stop(system_pid)
    end

    test "PubSub instances persist through system restarts" do
      # Start first system instance
      system_pid1 = ExESDB.System.start([store_id: :pubsub_dep_test_3])
      assert is_pid(system_pid1)

      # Get initial PubSub PIDs
      initial_pids = for name <- @pubsub_instances, do: {name, Process.whereis(name)}

      # Stop first system and start a new one
      Supervisor.stop(system_pid1)
      system_pid2 = ExESDB.System.start([store_id: :pubsub_dep_test_3])
      assert is_pid(system_pid2)

      # Get new PubSub PIDs
      new_pids = for name <- @pubsub_instances, do: {name, Process.whereis(name)}

      # Verify message passing still works
      test_topic = "test_topic_after_restart"
      test_message = "test_message_after_restart"

      for name <- @pubsub_instances do
        :ok = PubSub.subscribe(name, test_topic)
        :ok = PubSub.broadcast(name, test_topic, test_message)
        assert_receive ^test_message
      end

      # Clean up
      Supervisor.stop(system_pid2)
    end

    test "system handles concurrent PubSub operations" do
      system_pid = ExESDB.System.start([store_id: :pubsub_dep_test_4])
      assert is_pid(system_pid)

      # Start multiple concurrent subscriptions and broadcasts
      tasks = for i <- 1..10 do
        Task.async(fn ->
          topic = "concurrent_topic_#{i}"
          message = "concurrent_message_#{i}"

          # Subscribe and broadcast on all instances
          for name <- @pubsub_instances do
            :ok = PubSub.subscribe(name, topic)
            :ok = PubSub.broadcast(name, topic, message)
            assert_receive ^message, 1000
          end
        end)
      end

      # Wait for all operations to complete
      Task.await_many(tasks, 5000)

      # Clean up
      Supervisor.stop(system_pid)
    end
  end
end
