defmodule ExESDB.StoreNaming do
  @moduledoc """
  Helper module for creating store-specific GenServer names.

  This module provides utilities for generating store-specific names for GenServers,
  allowing multiple ExESDB instances to run on the same node with different stores.

  ## Usage

  Instead of using `name: __MODULE__` in GenServer registration, use:

      name: ExESDB.StoreNaming.genserver_name(__MODULE__, store_id)

  This will create store-specific names like `:"ex_esdb_store_my_store"` when
  a store_id is provided, or fall back to the module name for backward compatibility.

  ## Valid Process Names

  This module ensures that all generated names are valid for use with GenServers,
  Supervisors, and other OTP processes. The generated names are simple atoms that
  can be registered locally, which is compatible with Elixir's process naming
  requirements.
  """

  @doc """
  Generate a store-specific name for a GenServer.

  This function creates unique GenServer names based on the module and store_id,
  allowing multiple instances of the same GenServer to run with different stores.

  The function returns a valid process name that can be used for GenServers,
  Supervisors, and other OTP processes. When a store_id is provided, it creates
  a unique atom by combining the module name with the store_id. When no store_id
  is provided, it falls back to the module name for backward compatibility.

  ## Parameters

  * `module` - The GenServer module (typically `__MODULE__`)
  * `store_id` - The store identifier (string or atom)

  ## Examples

      iex> ExESDB.StoreNaming.genserver_name(ExESDB.Store, "my_store")
      :"ex_esdb_store_my_store"
      
      iex> ExESDB.StoreNaming.genserver_name(ExESDB.Store, nil)
      ExESDB.Store
      
      iex> ExESDB.StoreNaming.genserver_name(ExESDB.LeaderWorker, "cluster_store")
      :"ex_esdb_leader_worker_cluster_store"
  """
  def genserver_name(module, store_id) when is_binary(store_id) do
    atom_name = module_to_atom(module)
    store_atom = String.to_atom(store_id)
    String.to_atom("#{atom_name}_#{store_atom}")
  end

  def genserver_name(module, store_id) when is_atom(store_id) and not is_nil(store_id) do
    atom_name = module_to_atom(module)
    String.to_atom("#{atom_name}_#{store_id}")
  end

  def genserver_name(module, _), do: module

  @doc """
  Generate a store-specific child spec id.

  This function creates unique child spec IDs based on the module and store_id,
  allowing multiple instances of the same supervisor child to run with different stores.

  ## Parameters

  * `module` - The GenServer module (typically `__MODULE__`)
  * `store_id` - The store identifier (string or atom)

  ## Examples

      iex> ExESDB.StoreNaming.child_spec_id(ExESDB.Store, "my_store")
      :"ex_esdb_store_my_store"
      
      iex> ExESDB.StoreNaming.child_spec_id(ExESDB.Store, nil)
      ExESDB.Store
  """
  def child_spec_id(module, store_id), do: genserver_name(module, store_id)

  @doc """
  Extract store_id from options.

  This is a convenience function to extract the store_id from the standard
  options keyword list passed to GenServers.

  ## Examples

      iex> ExESDB.StoreNaming.extract_store_id([store_id: "my_store", timeout: 5000])
      "my_store"
      
      iex> ExESDB.StoreNaming.extract_store_id([timeout: 5000])
      nil
  """
  def extract_store_id(opts) when is_list(opts) do
    Keyword.get(opts, :store_id)
  end

  def extract_store_id(_), do: nil
  
  @doc """
  Generate a store-specific name for partition supervisors like StreamsWriters, etc.
  
  This function creates unique names for global resources that would otherwise conflict
  between multiple ExESDB instances.
  
  ## Parameters
  
  * `base_name` - The base name atom (e.g., ExESDB.StreamsWriters)
  * `store_id` - The store identifier (string or atom)
  
  ## Examples
  
      iex> ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, "my_store")
      :"exesdb_streamswriters_my_store"
      
      iex> ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, nil)
      ExESDB.StreamsWriters
  """
  def partition_name(base_name, store_id) when is_binary(store_id) do
    base_atom = module_to_atom(base_name)
    store_atom = String.to_atom(store_id)
    String.to_atom("#{base_atom}_#{store_atom}")
  end
  
  def partition_name(base_name, store_id) when is_atom(store_id) and not is_nil(store_id) do
    base_atom = module_to_atom(base_name)
    String.to_atom("#{base_atom}_#{store_id}")
  end
  
  def partition_name(base_name, _), do: base_name
  
  # Private helper to convert module name to atom for naming
  defp module_to_atom(module) do
    module
    |> Module.split()
    |> Enum.map_join("_", &String.downcase/1)
    |> String.to_atom()
  end
end
