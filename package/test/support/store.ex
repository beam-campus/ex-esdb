defmodule ExESDB.TestSupport.Store do
  @moduledoc """
  Test support utilities for ExESDB store operations.
  """

  @doc """
  Returns a test store identifier for use in tests.
  """
  def store do
    :test_store_#{:rand.uniform(10000)}
  end

  @doc """
  Creates a test store with basic configuration.
  """
  def create_test_store(opts \\ []) do
    store_id = Keyword.get(opts, :store_id, store())
    data_dir = Keyword.get(opts, :data_dir, "/tmp/test_store_#{:rand.uniform(10000)}")
    
    test_opts = [
      store_id: store_id,
      data_dir: data_dir,
      timeout: 5000,
      db_type: :single,
      pub_sub: :"test_pubsub_#{:rand.uniform(1000)}",
      reader_idle_ms: 1000,
      writer_idle_ms: 1000
    ]
    
    opts = Keyword.merge(test_opts, opts)
    
    {:ok, store_id, opts}
  end

  @doc """
  Starts a test store system and returns the store ID and system PID.
  """
  def start_test_store(opts \\ []) do
    {:ok, store_id, store_opts} = create_test_store(opts)
    
    {:ok, system_pid} = ExESDB.System.start_link(store_opts)
    
    # Wait for system to be ready
    Process.sleep(1000)
    
    {:ok, store_id, system_pid, store_opts}
  end

  @doc """
  Stops a test store system and cleans up data directory.
  """
  def stop_test_store(system_pid, opts) do
    if Process.alive?(system_pid) do
      GenServer.stop(system_pid, :normal, 5000)
    end
    
    if data_dir = Keyword.get(opts, :data_dir) do
      File.rm_rf(data_dir)
    end
    
    :ok
  end
end
