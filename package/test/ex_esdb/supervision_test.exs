defmodule ExESDB.SupervisionTest do
  use ExUnit.Case, async: true
  
  describe "layered supervision architecture" do
    test "validates supervision tree structure" do
      # Test that all supervisors have proper child specs
      opts = [
        store_id: :test_store,
        timeout: 1000,
        data_dir: "/tmp/test_khepri"
      ]
      
      # Test CoreSystem child spec
      core_spec = ExESDB.CoreSystem.child_spec(opts)
      assert core_spec.id == :exesdb_coresystem_test_store
      assert core_spec.type == :supervisor
      
      # Test StoreSystem child spec
      store_spec = ExESDB.StoreSystem.child_spec(opts)
      assert store_spec.id == :exesdb_storesystem_test_store
      assert store_spec.type == :supervisor
      
      # Test PersistenceSystem child spec
      persistence_spec = ExESDB.PersistenceSystem.child_spec(opts)
      assert persistence_spec.id == :exesdb_persistencesystem_test_store
      assert persistence_spec.type == :supervisor
      
      # Test LeadershipSystem child spec
      leadership_spec = ExESDB.LeadershipSystem.child_spec(opts)
      assert leadership_spec.id == :exesdb_leadershipsystem_test_store
      assert leadership_spec.type == :supervisor
      
      # Test GatewaySystem child spec
      gateway_spec = ExESDB.GatewaySystem.child_spec(opts)
      assert gateway_spec.id == :exesdb_gatewaysystem_test_store
      assert gateway_spec.type == :supervisor
      
      # Test EmitterSystem child spec
      emitter_spec = ExESDB.EmitterSystem.child_spec(opts)
      assert emitter_spec.id == :exesdb_emittersystem_test_store
      assert emitter_spec.type == :supervisor
    end
  end
end
