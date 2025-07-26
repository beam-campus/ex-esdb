defmodule ExESDB.EmitterPubSubTest do
  use ExUnit.Case, async: false

  alias Phoenix.PubSub

  @test_store :emitter_test_store
  @test_selector "test_stream"

  setup do
    # Start PubSubSystem first to ensure PubSub is available
    {:ok, system_pid} = ExESDB.System.start([store_id: @test_store])

    # Create a unique topic for this test
    topic = "#{@test_store}:#{@test_selector}:#{System.unique_integer([:positive])}"
    emitter_name = Module.concat(ExESDB.EmitterWorker, topic)

    # Start an emitter worker
    {:ok, emitter} = ExESDB.EmitterWorker.start_link({@test_store, @test_selector, nil, emitter_name})

    # Set up test cleanup
    on_exit(fn ->
      try do
        if Process.alive?(emitter) do
          GenServer.stop(emitter, :normal)
        end
      catch
        _, _ -> :ok
      end

      try do
        if Process.alive?(system_pid) do
          Process.exit(system_pid, :normal)
        end
      catch
        _, _ -> :ok
      end
    end)

    # Return the test context
    {:ok, %{emitter: emitter, topic: topic, system_pid: system_pid}}
  end

  describe "Emitter worker PubSub behavior" do
    test "broadcasts events to :ex_esdb_events", %{emitter: emitter, topic: topic} do
      test_pid = self()
      test_event = %{
        event_id: "test-#{System.unique_integer([:positive])}",
        event_type: "test_event",
        data: %{test: true}
      }

      # Subscribe to :ex_esdb_events
      :ok = PubSub.subscribe(:ex_esdb_events, topic)
      
      # Send event to emitter
      send(emitter, {:broadcast, topic, test_event})

      # Should receive the event through :ex_esdb_events
      assert_receive {:events, [^test_event]}
    end

    test "forwards local events to :ex_esdb_events", %{emitter: emitter, topic: topic} do
      test_event = %{
        event_id: "test-#{System.unique_integer([:positive])}",
        event_type: "test_event",
        data: %{test: true}
      }

      # Subscribe to :ex_esdb_events
      :ok = PubSub.subscribe(:ex_esdb_events, topic)
      
      # Send local forward event to emitter
      send(emitter, {:forward_to_local, topic, test_event})

      # Should receive the event through :ex_esdb_events
      assert_receive {:events, [^test_event]}
    end

    test "sends all events exclusively to :ex_esdb_events", %{emitter: emitter, topic: topic} do
      test_event = %{
        event_id: "test-#{System.unique_integer([:positive])}",
        event_type: "test_event",
        data: %{test: true}
      }

      # Subscribe to all PubSub instances
      :ok = PubSub.subscribe(:ex_esdb_events, topic)
      :ok = PubSub.subscribe(:ex_esdb_system, topic)
      :ok = PubSub.subscribe(:ex_esdb_logging, topic)
      
      # Send event to emitter
      send(emitter, {:broadcast, topic, test_event})

      # Should receive exactly one event through :ex_esdb_events
      assert_receive {:events, [^test_event]}
      
      # Should not receive events through other PubSub instances
      refute_receive {:events, [^test_event]}, 100
    end

    test "preserves event batching through :ex_esdb_events", %{emitter: emitter, topic: topic} do
      test_events = for i <- 1..3 do
        %{
          event_id: "test-#{System.unique_integer([:positive])}",
          event_type: "test_event_#{i}",
          data: %{test: i}
        }
      end

      # Subscribe to :ex_esdb_events
      :ok = PubSub.subscribe(:ex_esdb_events, topic)
      
      # Send events one by one
      Enum.each(test_events, fn event ->
        send(emitter, {:broadcast, topic, event})
      end)

      # Should receive each event as a single-event batch
      for event <- test_events do
        assert_receive {:events, [^event]}
      end
    end

    test "emitter stops broadcasting when terminated", %{emitter: emitter, topic: topic} do
      test_event = %{
        event_id: "test-#{System.unique_integer([:positive])}",
        event_type: "test_event",
        data: %{test: true}
      }

      # Test pre-condition: Subscribe and verify events are flowing
      :ok = PubSub.subscribe(:ex_esdb_events, topic)
      send(emitter, {:broadcast, topic, %{test_event | event_id: "pre-test"}})
      assert_receive {:events, [%{event_id: "pre-test"}]}, 1000
      
      # Monitor the emitter process to track termination
      ref = Process.monitor(emitter)
      
      # Stop the emitter gently
      GenServer.stop(emitter, :normal)

      # Wait for the process to terminate
      receive do
        {:DOWN, ^ref, :process, ^emitter, _} -> :ok
      after
        1000 -> raise "emitter did not terminate"
      end

      # Verify post-condition: No events should be processed after shutdown
      send(emitter, {:broadcast, topic, test_event})
      refute_receive {:events, _}, 1000
    end
  end
end
