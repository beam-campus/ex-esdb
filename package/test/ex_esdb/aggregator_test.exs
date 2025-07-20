defmodule ExESDB.AggregatorTest do
  @moduledoc false
  use ExUnit.Case
  @tag :ex_esdb_aggregator
  @tag :ex_esdb_docs
  doctest ExESDB.Aggregator

  alias ExESDB.Aggregator, as: Aggregator

  describe "integration tests" do
    @tag :ex_esdb_aggregator
    test "complete workflow with folding and finalizing" do
      events = [
        %{name: "John", counter: 5},
        %{counter: {:sum, 10}, active: true},
        %{name: {:overwrite, "Jane"}, location: "New York"}
      ]

      folded_result = Aggregator.foldl(events)
      final_result = Aggregator.finalize_map(folded_result)

      assert final_result == %{
               name: "Jane",
               counter: 15,
               active: true,
               location: "New York"
             }
    end
  end
end
