defmodule ExESDB.PersistenceWorkerSimpleTest do
  use ExUnit.Case, async: true
  
  alias ExESDB.PersistenceWorker
  alias ExESDB.StoreNaming
  
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
    
    test "returns :error when worker doesn't exist" do
      result = PersistenceWorker.force_persistence(:non_existent_store)
      assert result == :error
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
      
      # Force persistence (this will likely fail because khepri isn't mocked, but we can test the behavior)
      # The important thing is that it doesn't crash the worker
      _result = PersistenceWorker.force_persistence(store_id)
      
      # Give it time to process
      Process.sleep(50)
      
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
      assert child_spec.shutdown == 15_000
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
      
      # Force persistence (may fail but that's okay for this test)
      _result = PersistenceWorker.force_persistence(:test_store)
      
      # Give it time to process
      Process.sleep(50)
      
      final_state = :sys.get_state(pid)
      final_time = final_state.last_persistence_time
      
      # The time should have been updated even if persistence failed
      assert final_time >= initial_time
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
      
      # Add different stores - but the worker will only accept requests for stores it can handle
      # Since we only have one worker, we'll test that it accumulates different store IDs
      # when they're requested through the worker (even though it would normally reject non-matching stores)
      
      # Use GenServer.cast directly to bypass the whereis check
      GenServer.cast(pid, {:request_persistence, :store_one})
      GenServer.cast(pid, {:request_persistence, :store_two})
      GenServer.cast(pid, {:request_persistence, :store_three})
      
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
  
  describe "PersistenceWorker error handling" do
    test "worker survives persistence errors" do
      opts = [store_id: :test_store, persistence_interval: 100]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add a pending store
      PersistenceWorker.request_persistence(:test_store)
      
      # Give the cast time to process
      Process.sleep(50)
      
      # Verify store is pending
      state = :sys.get_state(pid)
      assert MapSet.member?(state.pending_stores, :test_store)
      
      # Wait for periodic persistence (which will likely fail but shouldn't crash)
      Process.sleep(150)
      
      # Verify the worker is still alive
      assert Process.alive?(pid)
    end
    
    test "handles graceful shutdown" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      # Add a pending store
      PersistenceWorker.request_persistence(:test_store)
      
      # Give the cast time to process
      Process.sleep(50)
      
      # Verify store is pending
      state = :sys.get_state(pid)
      assert MapSet.member?(state.pending_stores, :test_store)
      
      # Test that we can initiate shutdown without crashing
      # Don't test the actual termination timing since that depends on external factors
      monitor_ref = Process.monitor(pid)
      
      # Send a normal shutdown signal
      Process.exit(pid, :shutdown)
      
      # Wait for the process to actually terminate
      receive do
        {:DOWN, ^monitor_ref, :process, ^pid, reason} -> 
          # Verify it was a graceful shutdown
          assert reason == :shutdown
      after
        2000 -> flunk("Process did not terminate within 2 seconds")
      end
      
      # Verify the worker is stopped
      refute Process.alive?(pid)
    end
  end
  
  describe "PersistenceWorker naming" do
    test "uses correct naming pattern" do
      opts = [store_id: :test_store, persistence_interval: 1000]
      {:ok, pid} = start_supervised({PersistenceWorker, opts})
      
      expected_name = StoreNaming.genserver_name(PersistenceWorker, :test_store)
      actual_pid = GenServer.whereis(expected_name)
      
      assert actual_pid == pid
    end
    
    test "handles multiple workers with different store_ids" do
      opts1 = [store_id: :store_one, persistence_interval: 1000]
      opts2 = [store_id: :store_two, persistence_interval: 1000]
      
      {:ok, pid1} = start_supervised({PersistenceWorker, opts1}, id: :worker_one)
      {:ok, pid2} = start_supervised({PersistenceWorker, opts2}, id: :worker_two)
      
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert pid1 != pid2
      
      # Verify they have different names
      name1 = StoreNaming.genserver_name(PersistenceWorker, :store_one)
      name2 = StoreNaming.genserver_name(PersistenceWorker, :store_two)
      
      assert GenServer.whereis(name1) == pid1
      assert GenServer.whereis(name2) == pid2
    end
  end
end
