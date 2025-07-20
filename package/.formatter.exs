
[
  plugins: [
    Phoenix.LiveView.HTMLFormatter,  # Existing
  ],
  inputs: [
    "mix.exs",
    "config/*.exs",
    "{lib,test}/**/*.{ex,exs}",      # Explicit Elixir pattern
    "src/**/*.{erl,hrl}"             # Add Erlang file patterns
  ],
  subdirectories: ["./*"]
]

