import Config

config :forecaster, :mqtt,
  host: System.get_env("MQTT_HOST") || "127.0.0.1",
  port: System.get_env("MQTT_PORT") || 1883,
  username: System.get_env("MQTT_USER") || nil,
  password: System.get_env("MQTT_PW") || nil,
  namespace: System.get_env("MQTT_NAMESPACE") || "home/get/forecast"

config :forecaster, :meteo, place: System.get_env("FORECAST_PLACE") || "berlin_germany_2950159"

config :forecaster, :accuweather,
  country: System.get_env("FORECAST_COUNTRY") || "de",
  place_name: System.get_env("FORECAST_PLACE_NAME") || "berlin",
  place_id: System.get_env("FORECAST_PLACE_ID") || "167783"

config :forecaster, timezone: System.get_env("TZ") || "Europe/Berlin"
