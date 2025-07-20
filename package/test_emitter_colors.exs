#!/usr/bin/env elixir

# Test script to demonstrate the enhanced EmitterWorker and EmitterPool logging

defmodule TestEmitterColors do
  alias BCUtils.ColorFuncs, as: CF
  
  defp app_prefix, do: ""
  
  def emitter_system(pid, msg),
    do:
      "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}] #{app_prefix()} [#{CF.yellow_on_black()}EMITTER SYSTEM#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def emitter_pool(pid, msg),
    do: "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}] #{app_prefix()} [#{CF.yellow_on_black()}EMITTER POOL#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def emitter_worker(pid, msg),
    do: "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}] #{app_prefix()} [#{CF.yellow_on_black()}EMITTER#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def demo do
    fake_pid = self()
    
    IO.puts("\n" <> "═" * 70)
    IO.puts("DEMONSTRATION: Enhanced EmitterSystem Logging")
    IO.puts("═" * 70 <> "\n")
    
    # EmitterSystem startup
    IO.puts("")
    IO.puts("\n═══════════════════════════════════════════════════════════════")
    IO.puts(emitter_system(fake_pid, "🔥 SYSTEM ACTIVATION 🔥 Store: test_store | Components: 1 | Max Restarts: 10/60s"))
    IO.puts("═══════════════════════════════════════════════════════════════\n")
    IO.puts("")
    
    # EmitterPool startup
    IO.puts("")
    IO.puts("\n▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲")
    IO.puts(emitter_pool(fake_pid, "🚀 POOL STARTUP 🚀 Name: test_store:events_emitter_pool | Emitters: 5 | Store: test_store | Topic: events"))
    IO.puts("▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼\n")
    IO.puts("")
    
    # EmitterWorker activation
    IO.puts("")
    IO.puts(emitter_worker(fake_pid, "★★★ ACTIVATION ★★★ Topic: \"events\" | Scheduler: 1 | Store: test_store"))
    IO.puts("")
    
    # Event processing
    IO.puts(emitter_worker(fake_pid, "⚡ BROADCASTING Event: uuid-123(OrderCreated) → Topic: events"))
    IO.puts(emitter_worker(fake_pid, "🔄 FORWARDING Event: uuid-456(PaymentProcessed) → Local Topic: payments"))
    
    # EmitterWorker termination
    IO.puts("")
    IO.puts(emitter_worker(fake_pid, "💀💀💀 TERMINATION 💀💀💀 Reason: :normal | Store: test_store | Selector: events"))
    IO.puts("")
    
    # EmitterPool shutdown
    IO.puts("")
    IO.puts("\n❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗")
    IO.puts(emitter_pool(fake_pid, "🚨 POOL SHUTDOWN 🚨 Name: test_store:events_emitter_pool | Store: test_store | Topic: events"))
    IO.puts("❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗❗\n")
    IO.puts("")
    
    IO.puts("\n" <> "═" * 70)
    IO.puts("The EmitterSystem and EmitterWorkers now have MUCH more")
    IO.puts("prominent and visually distinct logging to highlight their")  
    IO.puts("critical importance in the ExESDB Event Sourcing Database!")
    IO.puts("═" * 70 <> "\n")
  end
end

# Only run demo if BCUtils is available
case Code.ensure_loaded(BCUtils.ColorFuncs) do
  {:module, _} -> TestEmitterColors.demo()
  {:error, _} -> 
    IO.puts("Note: BCUtils.ColorFuncs not loaded. Install dependencies with 'mix deps.get' to see colored output.")
    IO.puts("The actual enhanced logging will show bright colors and formatting when the system runs.")
end
