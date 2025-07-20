defmodule ExESDB.StoreInfo do
  @moduledoc """
    This module provides functions to get information about the EXESDB event store.
  """

  import ExESDB.Khepri.Conditions

  def get_streams_raw(store),
    do:
      store
      |> :khepri.fold(
        [:streams, if_node_exists(exists: true)],
        fn path, props, acc -> acc ++ [{path, props}] end,
        [],
        %{props_to_return: [:child_list_length]}
      )

  @doc """
    Returns the list of streams in the store.
  """
  def get_streams!(store) do
    case store
         |> get_streams_raw() do
      {:ok, streams} ->
        streams
        |> Stream.map(fn {[:streams, stream_name], %{child_list_length: nbr_of_events}} ->
          {stream_name, nbr_of_events}
        end)
        |> Enum.to_list()

      result ->
        result
    end
  end
end
