defmodule ExESDB.LoggingPublisher do
  @moduledoc """
  Helper module for publishing structured logging events to the :ex_esdb_logging PubSub topic.
  
  This module provides a clean API for components to publish logging events instead of
  using direct terminal output.
  """
  
  alias Phoenix.PubSub
  
  @pubsub_name :ex_esdb_logging
  
  @doc """
  Publishes a logging event to the appropriate topic.
  
  ## Parameters
  - `component`: The component type (e.g., :emitter_pool, :emitter_worker, :emitter_system)
  - `event_type`: The type of event (e.g., :startup, :shutdown, :action, :health, :error)
  - `store_id`: The store identifier
  - `message`: The log message
  - `metadata`: Additional metadata (default: %{})
  
  ## Examples
  
      iex> LoggingPublisher.publish(:emitter_pool, :startup, :my_store, "Pool started", %{pool_size: 3})
      :ok
      
      iex> LoggingPublisher.publish(:emitter_worker, :action, :my_store, "Processing event", %{event_id: "123"})
      :ok
  """
  def publish(component, event_type, store_id, message, metadata \\ %{}) do
    event = %{
      component: component,
      event_type: event_type,
      store_id: store_id,
      pid: self(),
      timestamp: DateTime.utc_now(),
      message: message,
      metadata: metadata
    }
    
    # Publish to both a component-specific topic and a store-specific topic
    component_topic = "logging:#{component}"
    store_topic = "logging:store:#{store_id}"
    
    PubSub.broadcast(@pubsub_name, component_topic, {:log_event, event})
    PubSub.broadcast(@pubsub_name, store_topic, {:log_event, event})
    
    :ok
  end
  
  @doc """
  Convenience functions for common logging scenarios
  """
  
  def startup(component, store_id, message, metadata \\ %{}) do
    publish(component, :startup, store_id, message, metadata)
  end
  
  def shutdown(component, store_id, message, metadata \\ %{}) do
    publish(component, :shutdown, store_id, message, metadata)
  end
  
  def action(component, store_id, message, metadata \\ %{}) do
    publish(component, :action, store_id, message, metadata)
  end
  
  def health(component, store_id, message, metadata \\ %{}) do
    publish(component, :health, store_id, message, metadata)
  end
  
  def error(component, store_id, message, metadata \\ %{}) do
    publish(component, :error, store_id, message, metadata)
  end
end
