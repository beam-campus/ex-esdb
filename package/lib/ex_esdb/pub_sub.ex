defmodule ExESDB.PubSub do
  @moduledoc """
  Phoenix PubSub configuration for ExESDB.
  
  This module provides a centralized PubSub instance for ExESDB internal coordination
  and external event broadcasting.
  """
  
  def child_spec(opts) do
    store_id = ExESDB.StoreNaming.extract_store_id(opts)
    
    # Return the standard Phoenix.PubSub child_spec
    spec = Phoenix.PubSub.child_spec(name: ExESDB.PubSub)
    
    # Override the id to make it store-specific
    %{spec | id: ExESDB.StoreNaming.child_spec_id(__MODULE__, store_id)}
  end
end
