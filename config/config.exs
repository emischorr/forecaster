import Config

config :logger,
  backends: [:console]

config :logger, :console,
  level: :info

config :hound, port: 8910, driver: "selenium" # start 'phantomjs --wd'
#config :hound, driver: "phantomjs", browser: "firefox"
#config :hound, driver: "chrome_driver"
# config :hound, driver: "chrome_driver", browser: "chrome_headless"
#config :hound, browser: "safari" # start selenium-server
#config :hound, port: 1234, browser: "firefox"

config :forecaster, update_interval: :timer.hours(2)

import_config "#{config_env()}.exs"
