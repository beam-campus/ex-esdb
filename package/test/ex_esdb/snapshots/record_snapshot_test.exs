defmodule ExEsdb.Snapshots.RecordSnapshotTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias ExESDB.Snapshots, as: Snapshots

  alias ExESDB.Schema.SnapshotRecord, as: SnapshotRecord

  describe "record_snapshot/2" do
    @tag :ex_esdb_snapshots
    test "GIVEN a store
          WHEN record_snapshot is called with a snapshot record
          THEN it returns :ok" do
      store = ExESDB.TestSupport.Store.store()
      source_uuid = UUIDv7.generate()
      utc_now = DateTime.utc_now()

      snapshot_record = %SnapshotRecord{
        source_uuid: source_uuid,
        source_version: 1,
        source_type: "test",
        data: %{name: "John"},
        metadata: %{},
        created_at: utc_now,
        created_epoch: utc_now |> DateTime.to_unix(:millisecond)
      }

      assert Snapshots.record_snapshot(store, snapshot_record) == :ok
    end
  end
end
