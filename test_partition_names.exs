#!/usr/bin/env elixir

# Simple test script to verify store-specific partition names are working correctly

# Add the system directory to the path
Code.append_path("/home/rl/work/github.com/beam-campus/ex-esdb/system/_build/dev/lib/ex_esdb/ebin")

# Test the StoreNaming module
IO.puts("🧪 Testing ExESDB.StoreNaming.partition_name/2 function...")
IO.puts("=" |> String.duplicate(60))

# Test cases
test_cases = [
  {ExESDB.StreamsWriters, "store_one"},
  {ExESDB.StreamsReaders, "store_one"},
  {ExESDB.SnapshotsWriters, "store_one"},
  {ExESDB.SnapshotsReaders, "store_one"},
  {ExESDB.EmitterPools, "store_one"},
  {ExESDB.GatewayWorkers, "store_one"},
  {ExESDB.StreamsWriters, "store_two"},
  {ExESDB.StreamsReaders, "store_two"},
  {ExESDB.SnapshotsWriters, "store_two"},
  {ExESDB.SnapshotsReaders, "store_two"},
  {ExESDB.EmitterPools, "store_two"},
  {ExESDB.GatewayWorkers, "store_two"},
  {ExESDB.StreamsWriters, nil},
  {ExESDB.StreamsReaders, nil},
]

IO.puts("Testing store-specific partition names:")
IO.puts("")

# Test each case
Enum.each(test_cases, fn {base_name, store_id} ->
  result = ExESDB.StoreNaming.partition_name(base_name, store_id)
  
  store_display = case store_id do
    nil -> "nil"
    id -> "\"#{id}\""
  end
  
  IO.puts("  #{inspect(base_name)}, #{store_display} -> #{inspect(result)}")
end)

IO.puts("")
IO.puts("✅ Verifying uniqueness...")

# Test uniqueness - store_one and store_two should have different names
store_one_names = [
  ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, "store_one"),
  ExESDB.StoreNaming.partition_name(ExESDB.StreamsReaders, "store_one"),
  ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsWriters, "store_one"),
  ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsReaders, "store_one"),
  ExESDB.StoreNaming.partition_name(ExESDB.EmitterPools, "store_one"),
  ExESDB.StoreNaming.partition_name(ExESDB.GatewayWorkers, "store_one")
]

store_two_names = [
  ExESDB.StoreNaming.partition_name(ExESDB.StreamsWriters, "store_two"),
  ExESDB.StoreNaming.partition_name(ExESDB.StreamsReaders, "store_two"),
  ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsWriters, "store_two"),
  ExESDB.StoreNaming.partition_name(ExESDB.SnapshotsReaders, "store_two"),
  ExESDB.StoreNaming.partition_name(ExESDB.EmitterPools, "store_two"),
  ExESDB.StoreNaming.partition_name(ExESDB.GatewayWorkers, "store_two")
]

# Check if any names overlap
common_names = MapSet.intersection(MapSet.new(store_one_names), MapSet.new(store_two_names))

if MapSet.size(common_names) == 0 do
  IO.puts("✅ All partition names are unique between stores!")
else
  IO.puts("❌ Found overlapping names: #{inspect(MapSet.to_list(common_names))}")
end

# Test backward compatibility - nil should return the original name
IO.puts("")
IO.puts("✅ Testing backward compatibility...")
nil_cases = [
  {ExESDB.StreamsWriters, ExESDB.StreamsWriters},
  {ExESDB.StreamsReaders, ExESDB.StreamsReaders},
  {ExESDB.SnapshotsWriters, ExESDB.SnapshotsWriters},
  {ExESDB.SnapshotsReaders, ExESDB.SnapshotsReaders},
  {ExESDB.EmitterPools, ExESDB.EmitterPools},
  {ExESDB.GatewayWorkers, ExESDB.GatewayWorkers}
]

all_nil_correct = Enum.all?(nil_cases, fn {base_name, expected} ->
  result = ExESDB.StoreNaming.partition_name(base_name, nil)
  result == expected
end)

if all_nil_correct do
  IO.puts("✅ Backward compatibility works - nil returns original names")
else
  IO.puts("❌ Backward compatibility failed")
end

IO.puts("")
IO.puts("🎉 Partition naming test completed!")
IO.puts("=" |> String.duplicate(60))
