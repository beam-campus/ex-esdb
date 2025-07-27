defmodule ExESDB.LoggingPublisherTest do
  use ExUnit.Case, async: true
  
  alias ExESDB.LoggingPublisher
  alias Phoenix.PubSub
  
  @pubsub_name :ex_esdb_logging
  @test_store_id :test_store_logging
  
  setup do
    # Subscribe to logging events for testing
    component_topic = "logging:emitter_system"
    store_topic = "logging:store:#{@test_store_id}"
    
    :ok = PubSub.subscribe(@pubsub_name, component_topic)
    :ok = PubSub.subscribe(@pubsub_name, store_topic)
    
    %{
      component_topic: component_topic,
      store_topic: store_topic
    }
  end
  
  describe "publish/5" do
    test "publishes logging events to both component and store topics" do
      message = "Test message"
      metadata = %{test: true}
      
      :ok = LoggingPublisher.publish(:emitter_system, :startup, @test_store_id, message, metadata)
      
      # Should receive the event on component topic
      assert_receive {:log_event, component_event}, 100
      assert component_event.component == :emitter_system
      assert component_event.event_type == :startup
      assert component_event.store_id == @test_store_id
      assert component_event.message == message
      assert component_event.metadata == metadata
      assert component_event.pid == self()
      assert %DateTime{} = component_event.timestamp
      
      # Should also receive the event on store topic
      assert_receive {:log_event, store_event}, 100
      assert store_event == component_event
    end
    
    test "publishes events with default empty metadata" do
      message = "Test without metadata"
      
      :ok = LoggingPublisher.publish(:emitter_pool, :shutdown, @test_store_id, message)
      
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_pool
      assert event.event_type == :shutdown
      assert event.metadata == %{}
    end
  end
  
  describe "convenience functions" do
    test "startup/4 publishes startup events" do
      :ok = LoggingPublisher.startup(:emitter_worker, @test_store_id, "Starting up")
      
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_worker
      assert event.event_type == :startup
      assert event.message == "Starting up"
    end
    
    test "shutdown/4 publishes shutdown events" do
      metadata = %{reason: :normal}
      :ok = LoggingPublisher.shutdown(:emitter_pool, @test_store_id, "Shutting down", metadata)
      
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_pool
      assert event.event_type == :shutdown
      assert event.message == "Shutting down"
      assert event.metadata == metadata
    end
    
    test "action/4 publishes action events" do
      :ok = LoggingPublisher.action(:emitter_worker, @test_store_id, "Processing event")
      
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_worker
      assert event.event_type == :action
      assert event.message == "Processing event"
    end
    
    test "health/4 publishes health events" do
      :ok = LoggingPublisher.health(:emitter_worker, @test_store_id, "Health check passed")
      
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_worker
      assert event.event_type == :health
      assert event.message == "Health check passed"
    end
    
    test "error/4 publishes error events" do
      :ok = LoggingPublisher.error(:emitter_system, @test_store_id, "Something went wrong")
      
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_system
      assert event.event_type == :error
      assert event.message == "Something went wrong"
    end
  end
  
  describe "event structure" do
    test "events contain all required fields with correct types" do
      :ok = LoggingPublisher.startup(:emitter_system, @test_store_id, "Test", %{key: "value"})
      
      assert_receive {:log_event, event}, 100
      
      # Verify all fields exist and have correct types
      assert is_atom(event.component)
      assert is_atom(event.event_type)
      assert is_atom(event.store_id)
      assert is_pid(event.pid)
      assert %DateTime{} = event.timestamp
      assert is_binary(event.message)
      assert is_map(event.metadata)
    end
    
    test "timestamp is accurate to within a few milliseconds" do
      before = DateTime.utc_now()
      :ok = LoggingPublisher.startup(:emitter_system, @test_store_id, "Test")
      after_time = DateTime.utc_now()
      
      assert_receive {:log_event, event}, 100
      
      assert DateTime.compare(event.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(event.timestamp, after_time) in [:lt, :eq]
    end
  end
  
  describe "topic routing" do
    test "events are published to correct component topic" do
      # Subscribe to a different component topic
      other_topic = "logging:emitter_pool"
      :ok = PubSub.subscribe(@pubsub_name, other_topic)
      
      # Publish to emitter_system
      :ok = LoggingPublisher.startup(:emitter_system, @test_store_id, "Test")
      
      # Should receive on emitter_system component topic (subscribed in setup)
      assert_receive {:log_event, event}, 100
      assert event.component == :emitter_system
      
      # Should receive on store topic (also subscribed in setup)
      assert_receive {:log_event, store_event}, 100
      assert store_event == event
      
      # Should NOT receive on other component topic
      refute_receive {:log_event, _event}, 50
    end
    
    test "events are published to correct store topic" do
      # Unsubscribe from current store topic first
      :ok = PubSub.unsubscribe(@pubsub_name, "logging:store:#{@test_store_id}")
      
      # Subscribe to a different store topic
      other_store_topic = "logging:store:other_store"
      :ok = PubSub.subscribe(@pubsub_name, other_store_topic)
      
      # Publish to our test store
      :ok = LoggingPublisher.startup(:emitter_system, @test_store_id, "Test")
      
      # Should receive on component topic (still subscribed from setup)
      assert_receive {:log_event, _event}, 100
      
      # Should NOT receive on other store topic
      refute_receive {:log_event, _event}, 50
    end
  end
end
