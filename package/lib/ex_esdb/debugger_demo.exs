#!/usr/bin/env elixir

# Demo script for ExESDB.Debugger
# Run with: elixir -r lib/ex_esdb/debugger.ex lib/ex_esdb/debugger_demo.exs

IO.puts("🔍 ExESDB Debugger Demo")
IO.puts("=" <> String.duplicate("=", 30))

# Compile the debugger module first
Code.require_file("lib/ex_esdb/debugger.ex", __DIR__ <> "/..")

alias ExESDB.Debugger

IO.puts("\n📚 Available commands:")
Debugger.help()

IO.puts("\n🎯 Example usage in REPL:")
IO.puts("""

# Start your application first
iex -S mix

# Then use these commands:
ExESDB.Debugger.overview()
ExESDB.Debugger.processes()  
ExESDB.Debugger.health()
ExESDB.Debugger.config()
ExESDB.Debugger.streams()
ExESDB.Debugger.subscriptions()
ExESDB.Debugger.performance()
ExESDB.Debugger.observer()  # Opens Erlang Observer GUI

# Investigate specific streams
ExESDB.Debugger.events("user-123", limit: 5)

# Trace function calls
ExESDB.Debugger.trace(ExESDB.StreamsWriter, :append_events, duration: 3000)

# Benchmark functions
ExESDB.Debugger.benchmark(fn -> 1..1000 |> Enum.sum() end, times: 1000)

# Show top processes
ExESDB.Debugger.top(limit: 5, sort_by: :memory)
""")

IO.puts("\n💡 Tips:")
IO.puts("- All functions work without arguments (auto-discover store)")
IO.puts("- Use store_id parameter for multi-store setups")
IO.puts("- Health check will identify common issues")
IO.puts("- Observer GUI provides real-time monitoring")
