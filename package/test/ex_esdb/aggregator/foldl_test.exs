defmodule ExESDB.Aggregator.FoldlTest do
  @moduledoc false
  use ExUnit.Case

  alias ExESDB.Aggregator

  describe "foldl/2" do
    @tag :bc_aggregator
    test "handles empty event list" do
      events = []
      result = Aggregator.foldl(events)
      assert result == %{}
    end

    test "applies a single event to an empty state" do
      events = [%{name: "John", age: 30}]
      result = Aggregator.foldl(events)
      assert result == %{name: "John", age: 30}
    end

    test "applies multiple events sequentially" do
      events = [
        %{name: "John", age: 30},
        %{location: "New York"}
      ]

      result = Aggregator.foldl(events)
      assert result == %{name: "John", age: 30, location: "New York"}
    end

    test "handles sum operations" do
      events = [
        %{counter: {:sum, 5}},
        %{counter: {:sum, 10}}
      ]

      result = Aggregator.foldl(events)
      assert result == %{counter: {:sum, 15}}
    end

    test "handles overwrite operations" do
      events = [
        %{name: "John"},
        %{name: {:overwrite, "Jane"}}
      ]

      result = Aggregator.foldl(events)
      assert result == %{name: "Jane"}
    end

    test "handles mixed operations" do
      events = [
        %{name: "John", counter: 5},
        %{counter: {:sum, 10}, status: "active"},
        %{name: {:overwrite, "Jane"}}
      ]

      result = Aggregator.foldl(events)
      assert result == %{name: "Jane", counter: {:sum, 15}, status: "active"}
    end

    test "handles initial state" do
      events = [
        %{counter: {:sum, 10}}
      ]

      initial_state = %{name: "John", counter: 5}
      result = Aggregator.foldl(events, initial_state)
      assert result == %{name: "John", counter: {:sum, 15}}
    end
  end

  describe "integration tests" do
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
