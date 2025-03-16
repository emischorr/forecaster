import Config

config :hound,
  driver: "selenium",
  host: System.get_env("SELENIUM_HOST") || "127.0.0.1",
  port: System.get_env("SELENIUM_PORT") || 4444

config :forecaster, :mqtt,
  host: System.get_env("MQTT_HOST") || "127.0.0.1",
  port: System.get_env("MQTT_PORT") || 1883,
  username: System.get_env("MQTT_USER") || nil,
  password: System.get_env("MQTT_PW") || nil,
  namespace: System.get_env("MQTT_NAMESPACE") || "home/get/forecast"

config :forecaster, place: System.get_env("FORECAST_PLACE") || "berlin_germany_2950159"
