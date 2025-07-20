defmodule ExESDB.Aggregator do
  @moduledoc """
    Aggregates events from an event stream using tagged rules:
    GIVEN: an Event of roughly this format:
     %{
      event_id: "1234567890",
      event_type: "user.birthday_celebrated:v1",
      stream_id: "celebrate-user-birthday-john",
      version: 1,
      data: %{
        name: "John",
        age: {:sum, 1},
        venue: {:overwrite, "New York"}
      },
      timestamp: ~U[2022-01-01 12:00:00Z],
      epoch: 1641013200,
      metadata: %{
        source_id: "1234567890"
      }
    }
  """

  @doc """
    Folds a list of events into a single map.
  """
  def foldl(sorted_events, state \\ %{}) do
  # Perform left fold (reduce)
    sorted_events
      |> Enum.reduce(state, fn evt, acc -> apply_evt(acc, evt) end)
  end

  defp get_current_num(map, key) do
    case map[key] do
      {:sum, value} -> value
      value when is_number(value) -> value
      nil -> 0

      _ -> 0
    end
  end

  defp apply_evt(state, event) do
    # Process each key-value pair in the event
    Map.keys(event)
    |> Enum.reduce(state, fn key, acc_map ->
      value = event[key]
      case value do
        {:sum, num} when is_number(num) ->
          current = get_current_num(acc_map, key)
          Map.put(acc_map, key, {:sum, current + num})
        {:overwrite, new_value} ->
          acc_map
          |> Map.put(key, new_value)
        _ ->
          Map.put(acc_map, key, value)
      end
    end)
  end

 def finalize_map(tagged_map) do
    Map.new(tagged_map, fn
      {key, {:sum, value}} -> {key, value}
      {key, {:overwrite, value}} -> {key, value}
      {key, value} -> {key, value}
    end)
  end
end
