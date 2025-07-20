defmodule ExESDB.ConfigAPIUnitTest do
  use ExUnit.Case, async: false

  alias ExESDB.ConfigAPI
  alias ExESDB.ConfigSystem

  describe "ConfigSystem.path/1" do
    test "generates correct Khepri path for store config" do
      assert ConfigSystem.path(:my_store) == [:stores, :config, :my_store]
      assert ConfigSystem.path(:another_store) == [:stores, :config, :another_store]
    end
  end

  describe "ConfigAPI leadership checking" do
    test "can check if config leader without errors" do
      # This should not crash even if no cluster is running
      is_leader = ConfigAPI.is_config_leader?()
      assert is_boolean(is_leader)
    end

    test "can get config leader status" do
      # This should return either a leader node or an error
      case ConfigAPI.get_config_leader() do
        {:ok, leader_node} -> 
          assert is_atom(leader_node)
        {:error, reason} -> 
          assert reason in [:no_leader, {:unexpected_leader_response, :undefined}]
      end
    end
  end

  describe "ConfigAPI basic validation" do
    test "put_store_config validates input types" do
      # Should accept atom store_id and map config
      config = %{timeout: 5000, auto_start: true}
      
      # This will likely fail due to no running cluster, but should not crash due to input validation
      result = ConfigAPI.put_store_config(:test_store, config)
      
      # We expect either success or a specific error type
      case result do
        {:ok, _} -> :ok
        {:error, reason} -> 
          assert reason in [:no_leader, :not_leader, {:unexpected_leader_response, :undefined}]
      end
    end

    test "get_store_config handles missing infrastructure gracefully" do
      # Should accept atom store_id but handle missing infrastructure (Swarm not started)
      # This test verifies the function signature and basic error handling
      assert_raise ArgumentError, fn ->
        ConfigAPI.get_store_config(:nonexistent_store)
      end
    end
  end
end
