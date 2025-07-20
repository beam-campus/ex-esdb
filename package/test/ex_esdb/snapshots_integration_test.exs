defmodule ExESDB.SnapshotsIntegrationTest do
  use ExUnit.Case, async: false
  
  require Logger
  
  alias ExESDB.System
  alias ExESDB.StreamsWriter
  alias ExESDB.SnapshotsWriter
  alias ExESDB.SnapshotsReader
  alias ExESDB.Schema.NewEvent
  
  @test_store_id :test_snapshots_store
  @test_data_dir "/tmp/test_snapshots_#{:rand.uniform(1000)}"
  
  setup_all do
    # Configure test environment
    opts = [
      store_id: @test_store_id,
      data_dir: @test_data_dir,
      timeout: 5000,
      db_type: :single,
      pub_sub: :test_pubsub,
      reader_idle_ms: 1000,
      writer_idle_ms: 1000
    ]
    
    Logger.info("Starting ExESDB.System for snapshots integration tests with opts: #{inspect(opts)}")
    
    # Start the system
    {:ok, system_pid} = System.start_link(opts)
    
    # Wait for system to be ready
    Process.sleep(2000)
    
    on_exit(fn ->
      Logger.info("Stopping ExESDB.System for snapshots integration tests")
      if Process.alive?(system_pid) do
        GenServer.stop(system_pid, :normal, 5000)
      end
      File.rm_rf(@test_data_dir)
    end)
    
    %{system_pid: system_pid, opts: opts}
  end
  
  describe "snapshot system" do
    test "snapshots system starts and is available" do
      # This is a basic test to verify the snapshots system is running
      # The actual snapshot API requires source_uuid and stream_uuid parameters
      # which are more complex to test without understanding the full domain model
      
      Logger.info("Testing snapshots system availability")
      
      # Test that we can create a basic snapshot record structure
      source_uuid = UUIDv7.generate()
      stream_uuid = UUIDv7.generate()
      version = 1
      
      snapshot_record = %{
        data: %{test: "data"},
        metadata: %{created_at: DateTime.utc_now()}
      }
      
      # Test that the SnapshotsWriter can accept a record_snapshot call
      # The actual API is: SnapshotsWriter.record_snapshot(store, source_uuid, stream_uuid, version, snapshot_record)
      result = SnapshotsWriter.record_snapshot(@test_store_id, source_uuid, stream_uuid, version, snapshot_record)
      
      # SnapshotsWriter returns :ok (not {:ok, _})
      assert result == :ok
      
      Logger.info("Successfully tested snapshots system basic functionality")
    end
    
    test "can read a snapshot using the actual API" do
      # Test reading snapshots using the existing API
      # The SnapshotsReader requires source_uuid and stream_uuid parameters
      
      source_uuid = UUIDv7.generate()
      stream_uuid = UUIDv7.generate()
      version = 1
      
      snapshot_record = %{
        data: %{counter: 10, status: "active"},
        metadata: %{created_at: DateTime.utc_now()}
      }
      
      # Record the snapshot
      :ok = SnapshotsWriter.record_snapshot(@test_store_id, source_uuid, stream_uuid, version, snapshot_record)
      
      Logger.info("Reading snapshot with source_uuid: #{source_uuid}, stream_uuid: #{stream_uuid}, version: #{version}")
      
      # Read the snapshot
      {:ok, read_snapshot} = SnapshotsReader.read_snapshot(@test_store_id, source_uuid, stream_uuid, version)
      
      assert read_snapshot.data.counter == 10
      assert read_snapshot.data.status == "active"
      
      Logger.info("Successfully read snapshot")
    end
    
    test "can list snapshots for a source and stream" do
      source_uuid = UUIDv7.generate()
      stream_uuid = UUIDv7.generate()
      
      # Create multiple snapshots
      snapshots = [
        {1, %{data: %{version: 1}, metadata: %{}}},
        {2, %{data: %{version: 2}, metadata: %{}}},
        {3, %{data: %{version: 3}, metadata: %{}}}
      ]
      
      # Record all snapshots
      Enum.each(snapshots, fn {version, snapshot_record} ->
        :ok = SnapshotsWriter.record_snapshot(@test_store_id, source_uuid, stream_uuid, version, snapshot_record)
      end)
      
      Logger.info("Listing snapshots for source_uuid: #{source_uuid}, stream_uuid: #{stream_uuid}")
      
      # List snapshots
      {:ok, snapshot_list} = SnapshotsReader.list_snapshots(@test_store_id, source_uuid, stream_uuid)
      
      assert length(snapshot_list) == 3
      
      Logger.info("Successfully listed #{length(snapshot_list)} snapshots")
    end
  end
end
