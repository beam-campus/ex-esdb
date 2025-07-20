defmodule ExESDB.ConfigSystemTest do
  use ExUnit.Case, async: false

  alias ExESDB.ConfigAPI

  setup do
    # Ensure clean test environment
    Application.stop(:ex_esdb)
    :ok = Application.start(:ex_esdb)
    
    # Wait for config store to be ready
    case ConfigAPI.wait_for_leader(5_000) do
      {:ok, _leader} -> :ok
      {:error, :timeout} -> 
        flunk("Config store leader not available within timeout")
    end
    
    :ok
  end

  describe "ConfigAPI" do
    test "can create and read store configurations" do
      store_id = :test_store_#{:rand.uniform(1000)}
      config = %{
        data_dir: "/tmp/test_store",
        timeout: 10_000,
        auto_start: true
      }

      # Create configuration
      assert {:ok, :created} = ConfigAPI.put_store_config(store_id, config)

      # Read configuration back
      assert {:ok, stored_config} = ConfigAPI.get_store_config(store_id)
      
      # Verify structure
      assert stored_config.store_id == store_id
      assert stored_config.config == config
      assert stored_config.status == :active
      assert Map.has_key?(stored_config.metadata, :created_at)
      assert Map.has_key?(stored_config.metadata, :version)
      assert stored_config.metadata.version == 1
    end

    test "can update existing store configurations" do
      store_id = :update_test_store_#{:rand.uniform(1000)}
      initial_config = %{timeout: 5_000}
      updated_config = %{timeout: 15_000, auto_start: false}

      # Create initial configuration
      assert {:ok, :created} = ConfigAPI.put_store_config(store_id, initial_config)

      # Update configuration
      assert {:ok, :updated} = ConfigAPI.put_store_config(store_id, updated_config)

      # Read updated configuration
      assert {:ok, stored_config} = ConfigAPI.get_store_config(store_id)
      
      # Verify update
      assert stored_config.config == updated_config
      assert stored_config.metadata.version == 2
    end

    test "can list all store configurations" do
      store1_id = :list_test_store1_#{:rand.uniform(1000)}
      store2_id = :list_test_store2_#{:rand.uniform(1000)}
      
      config1 = %{timeout: 5_000}
      config2 = %{timeout: 10_000}

      # Create two configurations
      assert {:ok, :created} = ConfigAPI.put_store_config(store1_id, config1)
      assert {:ok, :created} = ConfigAPI.put_store_config(store2_id, config2)

      # List configurations
      assert {:ok, configs} = ConfigAPI.list_store_configs()
      
      # Verify both stores are in the list
      assert Map.has_key?(configs, store1_id)
      assert Map.has_key?(configs, store2_id)
      assert configs[store1_id].config == config1
      assert configs[store2_id].config == config2
    end

    test "can delete store configurations" do
      store_id = :delete_test_store_#{:rand.uniform(1000)}
      config = %{timeout: 5_000}

      # Create configuration
      assert {:ok, :created} = ConfigAPI.put_store_config(store_id, config)

      # Verify it exists
      assert {:ok, _stored_config} = ConfigAPI.get_store_config(store_id)

      # Delete configuration
      assert {:ok, :deleted} = ConfigAPI.delete_store_config(store_id)

      # Verify it's gone
      assert {:error, :not_found} = ConfigAPI.get_store_config(store_id)
    end

    test "returns error for non-existent configurations" do
      non_existent_store = :non_existent_store_#{:rand.uniform(1000)}
      
      assert {:error, :not_found} = ConfigAPI.get_store_config(non_existent_store)
      assert {:error, :not_found} = ConfigAPI.delete_store_config(non_existent_store)
    end

    test "can check leadership status" do
      # Should be able to check if this node is the config leader
      is_leader = ConfigAPI.is_config_leader?()
      assert is_boolean(is_leader)

      # Should be able to get the current leader
      case ConfigAPI.get_config_leader() do
        {:ok, leader_node} -> 
          assert is_atom(leader_node)
        {:error, :no_leader} -> 
          # This is also acceptable during startup
          :ok
      end
    end
  end
end
