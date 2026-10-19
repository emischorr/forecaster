defmodule Forecaster.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.2.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        forecaster: [
          applications: [forecaster: :permanent, pv_forecast: :permanent],
          include_executables_for: [:unix]
        ]
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  defp deps do
    []
  end
end
