defmodule ExESDB.Topics do
  @moduledoc """
    A module to calculate topic identifiers
  """

  def selector_hash(selector) do
    :erlang.phash2(selector)
    |> Integer.to_string(16)
  end

  def sub_topic(:by_stream, "all-events", "$all"), do: "$all"
  def sub_topic(:by_stream, "transient", selector), do: selector
  def sub_topic(:by_stream, subscription_name, _selector), do: "$#{subscription_name}"
  def sub_topic(:by_event_type, "transient", selector), do: selector

  def sub_topic(:by_event_type, subscription_name, selector),
    do: "*#{subscription_name}-#{selector}"

  def sub_topic(:by_event_pattern, subscription_name, selector) do
    selector_hash =
      selector_hash(selector)

    "evt-pat-#{subscription_name}-#{selector_hash}"
  end

  def sub_topic(:by_event_payload, subscription_name, selector) do
    selector_hash =
      selector_hash(selector)

    "evt-pay-#{subscription_name}-#{selector_hash}"
  end
end
