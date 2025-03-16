import Config

config :logger,
  backends: [:console]

config :logger, :console, level: :info

# start 'phantomjs --wd'
# config :hound, port: 8910, driver: "selenium"
# config :hound, driver: "phantomjs", browser: "firefox"
# config :hound, driver: "chrome_driver"
# config :hound, driver: "chrome_driver", browser: "chrome_headless"
# config :hound, browser: "safari" # start selenium-server
# config :hound, port: 4444, browser: "firefox"

config :forecaster, update_interval: :timer.hours(2)

config :forecaster, Forecaster.Scheduler,
  jobs: [
    # Every hour
    {"1 * * * *", {Forecaster.Publisher, :publish_current_hour, []}}
  ]

import_config "#{config_env()}.exs"
