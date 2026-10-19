import Config

config :logger, level: :warning

config :nx, :default_backend, EXLA.Backend

# Tests start their own model servers and call the router directly
config :pv_forecast,
  model_path: "tmp/test/missing_model.bin",
  http_enabled: false,
  publish_enabled: false,
  defn_compiler: EXLA,
  inference_backend: EXLA.Backend
