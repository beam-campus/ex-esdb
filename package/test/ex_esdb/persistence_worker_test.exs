defmodule ExESDB.PersistenceWorkerTest do
  use ExUnit.Case, async: true
  
  alias ExESDB.PersistenceWorker
  alias ExESDB.StoreNaming
  
  # Import the :meck library for mocking
  import :meck
  
  describe "PersistenceWorker.start_link/1" do
    test "starts with valid options" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      assert Process.alive?(pid)
      assert GenServer.whereis(StoreNaming.genserver_name(PersistenceWorker, :test_store)) == pid
    end
    
    test "uses default persistence interval when not specified" do
      opts = [store_id: :test_store]
      
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      assert Process.alive?(pid)
      
      # Get the state to verify default interval
      state = :sys.get_state(pid)
      assert state.persistence_interval == 5_000
    end
    
    test "uses custom persistence interval from config" do
      opts = [store_id: :test_store, persistence_interval: 2_000]
      
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      assert Process.alive?(pid)
      
      # Get the state to verify custom interval
      state = :sys.get_state(pid)
      assert state.persistence_interval == 2_000
    end
    
    test "extracts store_id from options" do
      opts = [store_id: :custom_store, persistence_interval: 1000]
      
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      state = :sys.get_state(pid)
      assert state.store_id == :custom_store
    end
  end
  
  describe "PersistenceWorker.request_persistence/1" do
    setup do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      %{pid: pid, store_id: :test_store}
    end
    
    test "returns :ok when worker exists", %{store_id: store_id} do
      result = PersistenceWorker.request_persistence(store_id)
      assert result == :ok
    end
    
    test "adds store to pending stores", %{pid: pid, store_id: store_id} do
      PersistenceWorker.request_persistence(store_id)
      
      # Give the cast time to process
      Process.sleep(50)
      
      state = :sys.get_state(pid)
      assert MapSet.member?(state.pending_stores, store_id)
    end
    
    test "returns :error when worker doesn't exist" do
      result = PersistenceWorker.request_persistence(:non_existent_store)
      assert result == :error
    end
    
    test "handles multiple persistence requests for same store", %{pid: pid, store_id: store_id} do
      PersistenceWorker.request_persistence(store_id)
      PersistenceWorker.request_persistence(store_id)
      PersistenceWorker.request_persistence(store_id)
      
      # Give the casts time to process
      Process.sleep(50)
      
      state = :sys.get_state(pid)
      # Should only have one entry in the set
      assert MapSet.size(state.pending_stores) == 1
      assert MapSet.member?(state.pending_stores, store_id)
    end
  end
  
  describe "PersistenceWorker.force_persistence/1" do
    setup do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      %{pid: pid, store_id: :test_store}
    end
    
    test "returns :ok when successful", %{store_id: store_id} do
      # Mock successful khepri.fence call
      :meck.new(:khepri, [:unstick])
      :meck.expect(:khepri, :fence, fn(_store_id) -> :ok end)
      
      result = PersistenceWorker.force_persistence(store_id)
      assert result == :ok
      
      :meck.unload(:khepri)
    end
    
    test "clears pending stores after force persistence", %{pid: pid, store_id: store_id} do
      # Add some pending stores
      PersistenceWorker.request_persistence(store_id)
      PersistenceWorker.request_persistence(:other_store)
      
      # Give the casts time to process
      Process.sleep(50)
      
      # Verify stores are pending
      state = :sys.get_state(pid)
      assert MapSet.size(state.pending_stores) > 0
      
      # Force persistence
      :meck.new(:khepri, [:unstick])
      :meck.expect(:khepri, :fence, fn(_store_id) -> :ok end)
      
      PersistenceWorker.force_persistence(store_id)
      
      :meck.unload(:khepri)
      
      # Verify pending stores are cleared
      state = :sys.get_state(pid)
      assert MapSet.size(state.pending_stores) == 0
    end
    
    test "returns :error when worker doesn't exist" do
      result = PersistenceWorker.force_persistence(:non_existent_store)
      assert result == :error
    end
    
    test "handles persistence errors gracefully", %{store_id: store_id} do
      # Mock failing khepri.fence call
      :meck.new(:khepri, [:unstick])
      :meck.expect(:khepri, :fence, fn(_store_id) -> {:error, :timeout} end)
      
      result = PersistenceWorker.force_persistence(store_id)
      assert {:error, {:partial_success, 0, 1}} = result
      
      :meck.unload(:khepri)
    end
  end
  
  describe "PersistenceWorker periodic persistence" do
    test "processes pending stores periodically" do
      # Use a very short interval for testing
      opts = [store_id: :test_store, persistence_interval: 100]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add a pending store
      PersistenceWorker.request_persistence(:test_store)
      
      # Give the cast time to process
      Process.sleep(50)
      
      # Verify store is pending
      state = :sys.get_state(pid)
      assert MapSet.member?(state.pending_stores, :test_store)
      
      # Mock khepri.fence and wait for periodic persistence
      with_mock(:khepri, [fence: fn(_store_id) -> :ok end]) do
        # Wait for the periodic timer to fire
        Process.sleep(150)
        
        # Verify the fence was called
        assert_called(:khepri.fence(:test_store))
      end
      
      # Verify pending stores are cleared
      state = :sys.get_state(pid)
      assert MapSet.size(state.pending_stores) == 0
    end
  end
  
  describe "PersistenceWorker graceful shutdown" do
    test "persists pending stores on termination" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add a pending store
      PersistenceWorker.request_persistence(:test_store)
      
      # Give the cast time to process
      Process.sleep(50)
      
      # Mock khepri.fence for final persistence
      with_mock(:khepri, [fence: fn(_store_id) -> :ok end]) do
        # Stop the worker
        stop_supervised(pid)
        
        # Verify the fence was called during shutdown
        assert_called(:khepri.fence(:test_store))
      end
    end
    
    test "handles multiple pending stores on termination" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add multiple pending stores
      PersistenceWorker.request_persistence(:test_store)
      PersistenceWorker.request_persistence(:another_store)
      
      # Give the casts time to process
      Process.sleep(50)
      
      # Mock khepri.fence for final persistence
      with_mock(:khepri, [fence: fn(_store_id) -> :ok end]) do
        # Stop the worker
        stop_supervised(pid)
        
        # Verify fence was called for both stores
        assert_called(:khepri.fence(:test_store))
        assert_called(:khepri.fence(:another_store))
      end
    end
  end
  
  describe "PersistenceWorker error handling" do
    test "handles khepri fence errors gracefully" do
      opts = [store_id: :test_store, persistence_interval: 100]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add a pending store
      PersistenceWorker.request_persistence(:test_store)
      
      # Mock khepri.fence to return an error
      with_mock(:khepri, [fence: fn(_store_id) -> {:error, :timeout} end]) do
        # Wait for periodic persistence
        Process.sleep(150)
        
        # Verify the fence was called despite error
        assert_called(:khepri.fence(:test_store))
      end
      
      # Verify the worker is still alive
      assert Process.alive?(pid)
    end
    
    test "handles khepri fence exceptions gracefully" do
      opts = [store_id: :test_store, persistence_interval: 100]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add a pending store
      PersistenceWorker.request_persistence(:test_store)
      
      # Mock khepri.fence to raise an exception
      with_mock(:khepri, [fence: fn(_store_id) -> raise "test error" end]) do
        # Wait for periodic persistence
        Process.sleep(150)
        
        # Verify the fence was called
        assert_called(:khepri.fence(:test_store))
      end
      
      # Verify the worker is still alive
      assert Process.alive?(pid)
    end
  end
  
  describe "PersistenceWorker configuration" do
    test "respects otp_app configuration" do
      # Set up application environment
      Application.put_env(:test_app, :ex_esdb, [persistence_interval: 3000])
      
      opts = [store_id: :test_store, otp_app: :test_app]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      state = :sys.get_state(pid)
      assert state.persistence_interval == 3000
      
      # Cleanup
      Application.delete_env(:test_app, :ex_esdb)
    end
    
    test "uses Options module for configuration when otp_app not specified" do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      state = :sys.get_state(pid)
      # Should use the default from Options module
      assert state.persistence_interval == 5_000
    end
    
    test "direct persistence_interval option takes precedence" do
      Application.put_env(:test_app, :ex_esdb, [persistence_interval: 3000])
      
      opts = [store_id: :test_store, otp_app: :test_app, persistence_interval: 4000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      state = :sys.get_state(pid)
      assert state.persistence_interval == 4000
      
      # Cleanup
      Application.delete_env(:test_app, :ex_esdb)
    end
  end
  
  describe "PersistenceWorker child_spec" do
    test "generates correct child spec" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      
      child_spec = PersistenceWorker.child_spec(opts)
      
      assert child_spec.id == StoreNaming.child_spec_id(PersistenceWorker, :test_store)
      assert child_spec.start == {PersistenceWorker, :start_link, [opts]}
      assert child_spec.restart == :permanent
      assert child_spec.shutdown == 10_000
      assert child_spec.type == :worker
    end
  end
  
  describe "PersistenceWorker state management" do
    test "initializes with correct state" do
      opts = [store_id: :test_store, persistence_interval: 2000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      state = :sys.get_state(pid)
      
      assert state.store_id == :test_store
      assert state.persistence_interval == 2000
      assert is_reference(state.timer_ref)
      assert MapSet.size(state.pending_stores) == 0
      assert is_integer(state.last_persistence_time)
    end
    
    test "updates last_persistence_time on force_persistence" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      initial_state = :sys.get_state(pid)
      initial_time = initial_state.last_persistence_time
      
      # Wait a bit to ensure time difference
      Process.sleep(50)
      
      # Force persistence
      with_mock(:khepri, [fence: fn(_store_id) -> :ok end]) do
        PersistenceWorker.force_persistence(:test_store)
      end
      
      final_state = :sys.get_state(pid)
      final_time = final_state.last_persistence_time
      
      assert final_time > initial_time
    end
  end
  
  describe "PersistenceWorker batching behavior" do
    test "deduplicates multiple requests for same store" do
      opts = [store_id: :test_store, persistence_interval: 100]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add the same store multiple times
      PersistenceWorker.request_persistence(:test_store)
      PersistenceWorker.request_persistence(:test_store)
      PersistenceWorker.request_persistence(:test_store)
      
      # Give the casts time to process
      Process.sleep(50)
      
      state = :sys.get_state(pid)
      
      # Should only have one entry due to MapSet deduplication
      assert MapSet.size(state.pending_stores) == 1
      assert MapSet.member?(state.pending_stores, :test_store)
    end
    
    test "handles multiple different stores" do
      opts = [store_id: :test_store, persistence_interval: 100]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add different stores
      PersistenceWorker.request_persistence(:store_one)
      PersistenceWorker.request_persistence(:store_two)
      PersistenceWorker.request_persistence(:store_three)
      
      # Give the casts time to process
      Process.sleep(50)
      
      state = :sys.get_state(pid)
      
      # Should have all three stores
      assert MapSet.size(state.pending_stores) == 3
      assert MapSet.member?(state.pending_stores, :store_one)
      assert MapSet.member?(state.pending_stores, :store_two)
      assert MapSet.member?(state.pending_stores, :store_three)
    end
  end
end
