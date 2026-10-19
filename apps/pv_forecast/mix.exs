defmodule PvForecast.MixProject do
  use Mix.Project

  def project do
    [
      app: :pv_forecast,
      version: "0.2.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PvForecast.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:forecaster, in_umbrella: true},
      {:nx, "~> 0.10"},
      # Only needed for training; inference in prod runs on Nx.Defn.Evaluator
      {:exla, "~> 0.10", only: [:dev, :test]},
      {:axon, "~> 0.7"},
      {:bandit, "~> 1.13"},
      {:plug, "~> 1.20"},
      {:jason, "~> 1.4"}
    ]
  end
end
