defmodule ExESDB.Aggregator.FinalizeMapTest do
  @moduledoc false
  use ExUnit.Case
  alias ExESDB.Aggregator

  describe "finalize_map/1" do
    @tag :ex_esdb_aggregator
    test "unwraps tagged values in map" do
      tagged_map = %{
        name: "John",
        counter: {:sum, 15},
        status: {:overwrite, "active"}
      }

      result = Aggregator.finalize_map(tagged_map)

      assert result == %{
               name: "John",
               counter: 15,
               status: "active"
             }
    end

    @tag :ex_esdb_aggregator
    test "handles empty map" do
      result = Aggregator.finalize_map(%{})
      assert result == %{}
    end

    @tag :ex_esdb_aggregator
    test "preserves untagged values" do
      tagged_map = %{
        name: "John",
        age: 30,
        counter: {:sum, 15}
      }

      result = Aggregator.finalize_map(tagged_map)

      assert result == %{
               name: "John",
               age: 30,
               counter: 15
             }
    end
  end
end
