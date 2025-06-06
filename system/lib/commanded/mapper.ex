defmodule ExESDB.Commanded.Mapper do
  @moduledoc """
    A mapper for Commanded to use ExESDB as the event store.
  """
  alias Commanded.EventStore.EventData, as: EventData
  alias Commanded.EventStore.RecordedEvent, as: RecordedEvent
  alias Commanded.EventStore.SnapshotData, as: SnapshotData

  alias ExESDB.EventRecord, as: EventRecord
  alias ExESDB.NewEvent, as: NewEvent
  alias ExESDB.Schema.SnapshotRecord, as: SnapshotRecord

  require UUIDv7

  @doc """
    Converts a Commanded EventData struct to an ExESDB NewEvent struct.
  """
  @spec to_new_event(EventData.t()) :: NewEvent.t()
  def to_new_event(event_data)
      when is_struct(event_data, EventData),
      do: %NewEvent{
        event_id: UUIDv7.generate(),
        event_type: event_data.event_type,
        data_content_type: 1,
        metadata_content_type: 1,
        data: event_data.data,
        metadata: %{
          correlation_id: event_data.correlation_id,
          causation_id: event_data.causation_id,
          stream_version: nil
        }
      }

  @doc """
    Converts an ExESDB EventRecord struct to a Commanded RecordedEvent struct.
  """
  @spec to_recorded_event(EventRecord.t()) :: RecordedEvent.t()
  def to_recorded_event(
        %{
          metadata: %{
            stream_version: stream_version,
            correlation_id: correlation_id,
            causation_id: causation_id
          }
        } = event_record
      )
      when is_struct(event_record, EventRecord),
      do: %RecordedEvent{
        event_id: event_record.event_id,
        event_number: event_record.event_number,
        event_type: event_record.event_type,
        data: event_record.data,
        metadata: event_record.metadata,
        created_at: event_record.created,
        stream_id: event_record.event_stream_id,
        stream_version: stream_version,
        correlation_id: correlation_id,
        causation_id: causation_id
      }

  @doc """
    Converts an Commanded SnapshotData struct to an ExESDB SnapshotRecord struct.
  """
  @spec to_snapshot_record(SnapshotData.t()) :: SnapshotRecord.t()
  def to_snapshot_record(snapshot_data)
      when is_struct(snapshot_data, SnapshotData),
      do: %SnapshotRecord{
        source_uuid: snapshot_data.source_uuid,
        source_version: snapshot_data.source_version,
        source_type: snapshot_data.source_type,
        data: snapshot_data.data,
        metadata: snapshot_data.metadata,
        created_at: snapshot_data.created_at,
        created_epoch: DateTime.to_unix(snapshot_data.created_at, :millisecond)
      }

  @doc """
    Converts an ExESDB SnapshotRecord struct to a Commanded SnapshotData struct.
  """
  def to_snapshot_data(snapshot_record)
      when is_struct(snapshot_record, SnapshotRecord),
      do: %SnapshotData{
        source_uuid: snapshot_record.source_uuid,
        source_version: snapshot_record.source_version,
        source_type: snapshot_record.source_type,
        data: snapshot_record.data,
        metadata: snapshot_record.metadata,
        created_at: snapshot_record.created_at
      }
end
