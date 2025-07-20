defmodule Protoc do
  use Mix.Task

  def run(_args) do
    File.mkdir_p!("lib/generated")

    {result, _} =
      System.cmd(
        "protoc",
        [
          "--proto_path=priv/protos",
          "--elixir_out=lib/generated",
          "priv/protos/*.proto"
        ],
        stderr_to_stdout: true
      )

    IO.puts(result)
  end
end
