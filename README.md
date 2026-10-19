# Forecaster

Elixir umbrella application that fetches a weather forecast, predicts the daily production of a PV
installation from it and publishes both to a MQTT broker.
Useful for smart home automations or anything else that requires a weather or PV forecast.

| App                  | Purpose                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| `apps/forecaster`    | Scrapes the weather forecast (meteoblue + AccuWeather) and publishes it       |
| `apps/pv_forecast`   | Neural network ensemble (Nx/Axon) predicting daily PV production + HTTP API   |

Both apps run in one release. Every 2 hours the weather forecast is updated and published.
Each update triggers the PV forecast for all days with weather data, published under the same day topic.

## Weather backends

The HTML of meteoblue and AccuWeather is fetched via req and parsed with floki.
meteoblue is the base forecast (days 1-7, daily values + hourly temperature, precipitation, humidity, condition),
AccuWeather adds hourly cloud cover and brightness (days 1-4).
Data on their side isn't going to change too frequently, so please don't query in short intervals (be nice!).

To get the meteoblue place, search for your city, click on it and copy the ID out of the URL.
You can go with just the number (and get a redirect) or with the whole string like "berlin_germany_2950159".
For AccuWeather take country, name and ID from the URL of the hourly forecast
(`https://www.accuweather.com/en/<country>/<name>/hourly-weather-forecast/<id>`).

## PV forecast

The model predicts the daily production in kWh from the daily max temperature, sunshine hours, rain
and the solar declination (derived from the date). It is an ensemble of 3 small networks;
the mean is the forecast, min/max of the members indicate the uncertainty.

### Training

Training data is personal (production of your own installation) and is **not part of the repo**.
Put it in `data/training_data.csv` (gitignored) with one row per day:

```csv
date,max_temp,sunshine_hours,rain_mm,pv_production
2024-10-01,17.8,3.5,10.3,12.3
```

Weather values should come from a weather station near the installation. Then train with:

```sh
mix pv.train --data data/training_data.csv --output data/pv_forecast_ensemble.bin [--epochs 200]
```

Training uses EXLA, which is only a dev/test dependency. The release runs inference with plain Nx,
which is fast enough for the small model and keeps the image small.
A running instance picks up a new model file with `PvForecast.ModelServer.reload()` or a restart.

### HTTP API

Mainly to test the model or to predict the production for other weather conditions:

- `POST /api/v1/forecast` with one day, a list of days or `{"days": [...]}` (max 31):
  ```sh
  curl -XPOST localhost:4000/api/v1/forecast -H 'content-type: application/json' \
    -d '{"date":"2026-10-20","max_temp":14.2,"sunshine_hours":5.5,"rain_mm":0.0}'
  ```
  returns `{"unit":"kWh","forecasts":[{"date":"2026-10-20","energy_kwh":..,"min_kwh":..,"max_kwh":..}],...}`
- `GET /api/v1/model` - metadata and metrics of the loaded model
- `GET /health` - 200 when a model is loaded, 503 otherwise

## MQTT topics

All under the namespace (default `home/get/forecast`), retained:

| Topic                                   | Content                                                        |
| --------------------------------------- | -------------------------------------------------------------- |
| `status`                                | `online` / `offline` (last will)                               |
| `<day>/temp_max`, `temp_min`            | °C, day 1 is today                                             |
| `<day>/precip_max`, `sun`, `uv`         | mm (upper bound of the range), sunshine hours, UV index        |
| `<day>/pv_production`                   | predicted PV production in kWh                                 |
| `<day>/pv_production_min`, `_max`       | lowest / highest prediction of the ensemble members            |
| `current_hour/<key>`                    | `temperature`, `precip`, `precip_prop`, `humidity`, `condition`, `cloud_cover`, `brightness`; published every hour |

## Configuration

| Env variable          | Default                          |                                         |
| --------------------- | -------------------------------- | --------------------------------------- |
| `MQTT_HOST`           | `127.0.0.1`                      |                                         |
| `MQTT_PORT`           | `1883`                           |                                         |
| `MQTT_USER`, `MQTT_PW`| -                                |                                         |
| `MQTT_NAMESPACE`      | `home/get/forecast`              |                                         |
| `FORECAST_PLACE`      | `berlin_germany_2950159`         | meteoblue place                         |
| `FORECAST_COUNTRY`    | `de`                             | AccuWeather country                     |
| `FORECAST_PLACE_NAME` | `berlin`                         | AccuWeather place name                  |
| `FORECAST_PLACE_ID`   | `167783`                         | AccuWeather place ID                    |
| `TZ`                  | `Europe/Berlin`                  |                                         |
| `MODEL_PATH`          | `data/pv_forecast_ensemble.bin`  | `/data/pv_forecast_ensemble.bin` in Docker |
| `PV_TRAINING_DATA`    | `data/training_data.csv`         | only for training                       |
| `PORT`                | `4000`                           | HTTP API                                |

## Running with docker

```sh
docker build -t emischorr/forecaster:latest .
docker run -d -p 4000:4000 -v $PWD/data:/data:ro \
  -e MQTT_HOST=$MQTT_HOST -e MQTT_USER=$MQTT_USER -e MQTT_PW=$MQTT_PW \
  -e FORECAST_PLACE="berlin_germany_2950159" emischorr/forecaster:latest start
```

or use the compose file in `deployment/`: fill in the environment variables in
`deployment/docker-compose.yml`, put the model file in `deployment/data/` (mounted as `/data`) and run

```sh
docker compose -f deployment/docker-compose.yml up -d
```

Without a model file in the mounted `data` dir the weather is still published, the PV forecast is skipped.

### Local development

The `docker-compose.yml` in the root dir only starts a Mosquitto broker (port 1883, websockets on 9001)
to develop against, with its config, data and log under `.docker/mosquitto/`.
Mosquitto 2 only accepts local connections without a config, so create
`.docker/mosquitto/config/mosquitto.conf`, e.g.:

```
listener 1883
allow_anonymous true
```

Then start the broker and the apps (`MQTT_HOST` defaults to `127.0.0.1`):

```sh
docker compose up -d
iex -S mix
```

## Usage

```elixir
iex> Forecaster.Weather.forecast("a_place_1234567")
[
  {1, %{temp_max: "27", temp_min: "16", precip_max: "0", sun: "12", uv: "7",
        hour: %{
          0 => %{temperature: "4", precip: "0", precip_prop: "5", humidity: "90", condition: "Mostly cloudy"},
          ...
        }}},
  {2, %{temp_max: "28", temp_min: "11", precip_max: "0", sun: "13", uv: "6", hour: %{...}}},
  ...
]

iex> Forecaster.Scraper.get_forecasts() |> PvForecast.Publisher.forecast(Date.utc_today())
{:ok, [{1, %{pv_production: 6.1, pv_production_min: 5.4, pv_production_max: 6.9}}, ...]}
```

To query the PV model for any day + weather combination (like the HTTP API), build the features
and ask the running model server. Results are in kWh, one value per day in input order:

```elixir
iex> days = [
...>   %{date: ~D[2026-06-21], max_temp: 26.0, sunshine_hours: 14.0, rain_mm: 0.0},
...>   %{date: ~D[2026-12-21], max_temp: 3.0, sunshine_hours: 1.5, rain_mm: 4.2}
...> ]
iex> days |> Enum.map(&PvForecast.Model.features/1) |> Nx.tensor(type: :f32) |> PvForecast.ModelServer.predict()
{:ok, %{mean: [32.34, 2.59], min: [27.77, 2.06], max: [36.12, 3.01]}}

iex> PvForecast.ModelServer.info()
%{status: :ready, path: "data/pv_forecast_ensemble.bin", metadata: %{...}, loaded_at: ~U[...]}
```

Without a loaded model `predict/1` returns `{:error, :not_ready}`.
