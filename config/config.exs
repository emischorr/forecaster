import Config

config :logger,
  backends: [:console]

config :logger, :console, level: :info

config :forecaster, update_interval: :timer.hours(2)

config :forecaster, Forecaster.Scheduler,
  jobs: [
    # Every hour
    {"1 * * * *", {Forecaster.Publisher, :publish_current_hour, []}}
  ]

import_config "#{config_env()}.exs"
