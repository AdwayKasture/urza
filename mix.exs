defmodule Urza.MixProject do
  use Mix.Project

  def project do
    [
      app: :urza,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: application_mod()
    ]
  end

  # Use DevApplication in dev environment to start Oban + Repo
  # Production apps should use Urza.Application and start Oban themselves
  defp application_mod do
    if Mix.env() == :dev do
      {Urza.DevApplication, []}
    else
      {Urza.Application, []}
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:oban, "~> 2.20"},
      {:req_llm, "~> 1.5"},
      {:req, "~> 0.5"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:mox, "~> 1.2", only: [:dev, :test]}
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
