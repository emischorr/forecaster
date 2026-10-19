import Config

config :nx, :default_backend, EXLA.Backend

config :pv_forecast, defn_compiler: EXLA, inference_backend: EXLA.Backend
