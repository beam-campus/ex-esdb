defmodule ExESDB.Snapshots.ReadSnapshotTest do
  @moduledoc false
  use ExUnit.Case

  alias ExESDB.Snapshots

  alias ExESDB.Schema.SnapshotRecord

  describe "read_snapshot/2" do
    @tag :ex_esdb_snapshots
    test "GIVEN a store with a snapshot
          WHEN read_snapshot is called with the source_uuid
          THEN it returns the snapshot" do
      store = ExESDB.TestSupport.Store.store()
      source_uuid = UUIDv7.generate()

      snapshot_record = %SnapshotRecord{
        source_uuid: source_uuid,
        source_version: 1,
        source_type: "test",
        data: %{name: "John"},
        metadata: %{},
        created_at: DateTime.utc_now(),
        created_epoch: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      }

      assert Snapshots.record_snapshot(store, snapshot_record) == :ok
      assert Snapshots.read_snapshot(store, source_uuid) == {:ok, snapshot_record}
    end

    @tag :ex_esdb_snapshots
    test "GIVEN a store without a snapshot
          WHEN read_snapshot is called with the source_uuid
          THEN it returns an error" do
      store = ExESDB.TestSupport.Store.store()
      source_uuid = UUIDv7.generate()
      assert Snapshots.read_snapshot(store, source_uuid) == {:error, :not_found}
    end
  end
end
