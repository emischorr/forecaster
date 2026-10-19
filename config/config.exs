import Config

config :logger, :console, level: :info

# -- forecaster (weather) -----------------------------------------------------

config :forecaster, update_interval: :timer.hours(2)

config :forecaster, Forecaster.Scheduler,
  jobs: [
    # Every hour
    {"1 * * * *", {Forecaster.Publisher, :publish_current_hour, []}}
  ]

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# -- pv_forecast ----------------------------------------------------------------

config :pv_forecast,
  model_path: "data/pv_forecast_ensemble.bin",
  training_data_path: "data/training_data.csv",
  port: 4000,
  http_enabled: true,
  publish_enabled: true,
  # Small model, plain Nx is fast enough. Dev/test switch to EXLA (see dev.exs/test.exs).
  defn_compiler: Nx.Defn.Evaluator,
  inference_backend: Nx.BinaryBackend

import_config "#{config_env()}.exs"
