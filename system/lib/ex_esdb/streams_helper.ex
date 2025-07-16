defmodule ExESDB.StreamsHelper do
  @moduledoc """
    Provides helper functions for working with event store streams.
  """

  import ExESDB.Khepri.Conditions

  def calculate_versions(start_version, count, direction)
      when is_integer(start_version) and is_integer(count) and count > 0 do
    case direction do
      :forward -> start_version..(start_version + count - 1)
      :backward -> start_version..(start_version - count + 1)
    end
  end

  # Handle invalid inputs gracefully
  def calculate_versions(start_version, count, direction) do
    require Logger

    Logger.warning(
      "Invalid parameters for calculate_versions: start_version=#{inspect(start_version)}, count=#{inspect(count)}, direction=#{inspect(direction)}"
    )

    # Return empty range for invalid inputs
    0..-1
  end

  def stream_exists?(store, stream_id),
    do:
      store
      |> :khepri.exists([:streams, stream_id])

  def version_to_integer(padded_version)
      when is_binary(padded_version) do
    padded_version
    |> String.trim_leading("0")
    |> case do
      # Handle all-zero case
      "" -> 0
      num_str -> String.to_integer(num_str)
    end
  end

  def pad_version(version, length)
      when is_integer(version) and
             length > 0 do
    version
    |> Integer.to_string()
    |> String.pad_leading(length, "0")
  end

  @doc """
    Returns the version of the stream using 0-based indexing.
    ## Parameters
     - `store` is the name of the store.
     - `stream_id` is the name of the stream.

    ## Returns
     - `version` (0-based) or `-1` if the stream does not exist.
     This means:
     - New stream (no events): -1
     - Stream with 1 event: 0 (version of latest event)
     - Stream with 2 events: 1 (version of latest event)
     - etc.
  """
  @spec get_version!(
          store :: atom(),
          stream_id :: String.t()
        ) :: integer
  def get_version!(store, stream_id) do
    case store
         |> :khepri.count([
           :streams,
           stream_id,
           if_node_exists(exists: true)
         ]) do
      # No events in stream, so version is -1
      {:ok, 0} -> -1
      # Convert 1-based count to 0-based version
      {:ok, count} -> count - 1
      # Stream doesn't exist
      _ -> -1
    end
  end

  def to_event_record(
        %ExESDB.Schema.NewEvent{} = new_event,
        stream_id,
        version,
        created,
        created_epoch
      ),
      do: %ExESDB.Schema.EventRecord{
        event_stream_id: stream_id,
        event_number: version,
        event_id: new_event.event_id,
        event_type: new_event.event_type,
        data_content_type: new_event.data_content_type,
        metadata_content_type: new_event.metadata_content_type,
        data: new_event.data,
        metadata: new_event.metadata,
        created: created,
        created_epoch: created_epoch
      }
end
