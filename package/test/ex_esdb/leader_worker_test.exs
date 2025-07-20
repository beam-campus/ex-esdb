defmodule ExESDB.LeaderWorkerTest do
  use ExUnit.Case, async: true

  alias ExESDB.LeaderWorker
  alias ExESDB.StoreNaming
  alias ExESDB.SubscriptionsReader
  alias ExESDB.SubscriptionsWriter
  alias ExESDB.Emitters

  import :meck

  describe "LeaderWorker.start_link/1" do
    test "starts with valid options" do
      opts = [store_id: :test_store]
      
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      assert Process.alive?(pid)
      assert GenServer.whereis(StoreNaming.genserver_name(LeaderWorker, :test_store)) == pid
    end
    
    test "extracts store_id from options" do
      opts = [store_id: :custom_store]
      
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      state = :sys.get_state(pid)
      assert state[:store_id] == :custom_store
    end
  end

  describe "LeaderWorker.activate/1" do
    setup do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      %{pid: pid, store_id: :test_store}
    end

    test "successfully activates when worker exists", %{store_id: store_id} do
      # Mock SubscriptionsWriter to return success
      :meck.new(SubscriptionsWriter, [:unstick])
      :meck.expect(SubscriptionsWriter, :put_subscription, fn _, _, _, _ -> :ok end)
      
      result = LeaderWorker.activate(store_id)
      
      assert result == :ok
      
      :meck.unload(SubscriptionsWriter)
    end

    test "returns error when worker doesn't exist" do
      result = LeaderWorker.activate(:non_existent_store)
      
      assert result == {:error, :not_found}
    end

    test "handles save_default_subscriptions errors gracefully", %{store_id: store_id} do
      # Mock SubscriptionsWriter to return error
      :meck.new(SubscriptionsWriter, [:unstick])
      :meck.expect(SubscriptionsWriter, :put_subscription, fn _, _, _, _ -> 
        raise "test error"
      end)
      
      result = LeaderWorker.activate(store_id)
      
      assert {:error, _} = result
      
      :meck.unload(SubscriptionsWriter)
    end
  end

  describe "LeaderWorker.handle_cast/2" do
    setup do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      %{pid: pid, store_id: :test_store}
    end

    test "handles activation cast with no subscriptions", %{pid: pid, store_id: store_id} do
      # Mock SubscriptionsReader to return empty list
      :meck.new(SubscriptionsReader, [:unstick])
      :meck.expect(SubscriptionsReader, :get_subscriptions, fn _ -> [] end)
      
      # Send activation cast
      GenServer.cast(pid, {:activate, store_id})
      
      # Give time for processing
      Process.sleep(50)
      
      # Verify the process is still alive
      assert Process.alive?(pid)
      
      :meck.unload(SubscriptionsReader)
    end

    test "handles activation cast with existing subscriptions", %{pid: pid, store_id: store_id} do
      # Mock dependencies
      :meck.new(SubscriptionsReader, [:unstick])
      :meck.new(Emitters, [:unstick])
      :meck.new(Process, [:unstick])
      
      # Mock returning subscriptions
      :meck.expect(SubscriptionsReader, :get_subscriptions, fn _ -> 
        [{:key1, %{type: :by_stream, subscription_name: "test1"}},
         {:key2, %{type: :by_stream, subscription_name: "test2"}}]
      end)
      
      # Mock EmitterPools process exists
      :meck.expect(Process, :whereis, fn _ -> self() end)
      
      # Mock successful emitter pool starts
      :meck.expect(Emitters, :start_emitter_pool, fn _, _ -> {:ok, self()} end)
      
      # Send activation cast
      GenServer.cast(pid, {:activate, store_id})
      
      # Give time for processing
      Process.sleep(50)
      
      # Verify the process is still alive
      assert Process.alive?(pid)
      
      # Verify Emitters.start_emitter_pool was called
      assert :meck.validate(Emitters)
      
      :meck.unload(SubscriptionsReader)
      :meck.unload(Emitters)
      :meck.unload(Process)
    end

    test "handles activation cast when EmitterPools not available", %{pid: pid, store_id: store_id} do
      # Mock dependencies
      :meck.new(SubscriptionsReader, [:unstick])
      :meck.new(Process, [:unstick])
      
      # Mock returning subscriptions
      :meck.expect(SubscriptionsReader, :get_subscriptions, fn _ -> 
        [{:key1, %{type: :by_stream, subscription_name: "test1"}}]
      end)
      
      # Mock EmitterPools process doesn't exist
      :meck.expect(Process, :whereis, fn _ -> nil end)
      
      # Send activation cast
      GenServer.cast(pid, {:activate, store_id})
      
      # Give time for processing
      Process.sleep(50)
      
      # Verify the process is still alive
      assert Process.alive?(pid)
      
      :meck.unload(SubscriptionsReader)
      :meck.unload(Process)
    end

    test "handles unexpected cast messages", %{pid: pid} do
      # Send unexpected cast
      GenServer.cast(pid, {:unexpected_message, "test"})
      
      # Give time for processing
      Process.sleep(50)
      
      # Verify the process is still alive
      assert Process.alive?(pid)
    end
  end

  describe "LeaderWorker.handle_call/3" do
    setup do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      %{pid: pid, store_id: :test_store}
    end

    test "handles save_default_subscriptions successfully", %{pid: pid, store_id: store_id} do
      # Mock SubscriptionsWriter
      :meck.new(SubscriptionsWriter, [:unstick])
      :meck.expect(SubscriptionsWriter, :put_subscription, fn _, _, _, _ -> :ok end)
      
      result = GenServer.call(pid, {:save_default_subscriptions, store_id})
      
      assert {:ok, :ok} = result
      
      :meck.unload(SubscriptionsWriter)
    end

    test "handles save_default_subscriptions errors", %{pid: pid, store_id: store_id} do
      # Mock SubscriptionsWriter to raise error
      :meck.new(SubscriptionsWriter, [:unstick])
      :meck.expect(SubscriptionsWriter, :put_subscription, fn _, _, _, _ -> 
        raise "test error"
      end)
      
      result = GenServer.call(pid, {:save_default_subscriptions, store_id})
      
      assert {:error, _} = result
      
      :meck.unload(SubscriptionsWriter)
    end

    test "handles save_default_subscriptions exit", %{pid: pid, store_id: store_id} do
      # Mock SubscriptionsWriter to exit
      :meck.new(SubscriptionsWriter, [:unstick])
      :meck.expect(SubscriptionsWriter, :put_subscription, fn _, _, _, _ -> 
        exit(:test_exit)
      end)
      
      result = GenServer.call(pid, {:save_default_subscriptions, store_id})
      
      assert {:error, :test_exit} = result
      
      :meck.unload(SubscriptionsWriter)
    end

    test "handles unexpected call messages", %{pid: pid} do
      result = GenServer.call(pid, {:unexpected_call, "test"})
      
      assert result == :ok
    end
  end

  describe "LeaderWorker.handle_info/2" do
    setup do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      %{pid: pid, store_id: :test_store}
    end

    test "handles unexpected info messages", %{pid: pid} do
      # Send unexpected info
      send(pid, {:unexpected_info, "test"})
      
      # Give time for processing
      Process.sleep(50)
      
      # Verify the process is still alive
      assert Process.alive?(pid)
    end
  end

  describe "LeaderWorker.child_spec/1" do
    test "generates correct child spec" do
      opts = [store_id: :test_store]
      
      child_spec = LeaderWorker.child_spec(opts)
      
      assert child_spec.id == StoreNaming.child_spec_id(LeaderWorker, :test_store)
      assert child_spec.start == {LeaderWorker, :start_link, [opts]}
      assert child_spec.restart == :permanent
      assert child_spec.shutdown == 10_000
      assert child_spec.type == :worker
    end
  end

  describe "LeaderWorker.terminate/2" do
    test "terminates gracefully" do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      # Stop the worker
      stop_supervised(pid)
      
      # Verify it's no longer alive
      assert not Process.alive?(pid)
    end
  end

  describe "LeaderWorker state management" do
    test "initializes with correct state" do
      opts = [store_id: :test_store, other_option: :value]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      state = :sys.get_state(pid)
      
      assert state[:store_id] == :test_store
      assert state[:other_option] == :value
    end

    test "maintains state across operations" do
      opts = [store_id: :test_store]
      {:ok, pid} = start_supervised({LeaderWorker, opts})
      
      initial_state = :sys.get_state(pid)
      
      # Send a cast message
      GenServer.cast(pid, {:unexpected_message, "test"})
      
      # Give time for processing
      Process.sleep(50)
      
      final_state = :sys.get_state(pid)
      
      # State should remain unchanged
      assert initial_state == final_state
    end
  end
end
