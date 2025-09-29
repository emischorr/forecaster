defmodule Forecaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :forecaster,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Forecaster.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.10"},
      {:floki, "~> 0.36.0"},
      {:tortoise, "~> 0.10"},
      {:quantum, "~> 3.0"},
      {:tzdata, "~> 1.1"},
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
