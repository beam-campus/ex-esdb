defmodule RegGh.MixProject do
  use Mix.Project

  def project do
    [
      app: :reg_gh,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RegGh.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    ex_esdb_path = case System.get_env("MIX_ENV") do
      "prod" -> "/build_space/ex_esdb_package"  # Docker build path
      _ -> "../package/"  # Local development path
    end
    
    [
      {:ex_esdb, path: ex_esdb_path}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp releases do
    [
      reg_gh: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
