defmodule Forecaster.Publisher do
  @moduledoc """
  GenServer to publish the updated forecast for days as well as an hourly "measurement" to the MQTT broker.
  Daily forecasts get published whenever the scraper broadcasts a `:forecast_updated` event,
  while the forecast for the current hour is published every hour as a sort of measurement.

  Other apps can publish additional values under a day topic with `publish_daily/3`.

  The module sends also meta data to the MQTT broker on startup.
  """
  use GenServer
  require Logger

  alias Forecaster.Events
  alias Forecaster.MQTT
  alias Forecaster.Scraper

  # Client

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def publish_current_hour do
    GenServer.cast(__MODULE__, :publish_current_hour)
  end

  @doc "Publishes `value` as `key` under the topic of `day` (`<namespace>/<day>/<key>`)."
  def publish_daily(day, key, value) do
    GenServer.cast(__MODULE__, {:publish_daily, day, to_string(key), to_string(value)})
  end

  # Server (callbacks)

  @impl true
  def init(_opts) do
    Logger.info("Starting Publisher")
    Events.subscribe(:forecast_updated)
    {:ok, %{forecast_retry: false}, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    {:ok, mqtt_client} = MQTT.connect()
    MQTT.publish_meta(mqtt_client)
    {:noreply, Map.put(state, :mqtt_client, mqtt_client)}
  end

  @impl true
  def handle_cast(:publish_current_hour, state) do
    Logger.info("Publishing current forecast measurement")

    hour = timezone() |> DateTime.now!() |> Map.get(:hour)

    case Scraper.get_forecast(1) do
      {1, %{hour: %{^hour => forecast}}} ->
        publish_current_hour(forecast, state.mqtt_client)
        {:noreply, %{state | forecast_retry: false}}

      _else ->
        unless state.forecast_retry,
          do: Process.send_after(self(), :retry_current_hour, 60_000)

        {:noreply, %{state | forecast_retry: true}}
    end
  end

  def handle_cast({:publish_daily, day, key, value}, state) do
    MQTT.publish_daily_forecast(state.mqtt_client, day, key, value)
    {:noreply, state}
  end

  @impl true
  def handle_info({Events, :forecast_updated}, state) do
    Logger.info("Publishing daily forecast")

    Enum.each(Scraper.get_forecasts(), fn {day, forecast} ->
      publish_daily_forecast(forecast, day, state.mqtt_client)
    end)

    {:noreply, state}
  end

  def handle_info(:retry_current_hour, state) do
    handle_cast(:publish_current_hour, state)
  end

  defp publish_daily_forecast(forecast, day, mqtt_client) do
    forecast
    |> Map.drop([:hour])
    |> Enum.each(fn {key, value} ->
      MQTT.publish_daily_forecast(mqtt_client, day, Atom.to_string(key), value)
    end)
  end

  defp publish_current_hour(forecast, mqtt_client) do
    Enum.each(forecast, fn {key, value} ->
      MQTT.publish_current_hour(mqtt_client, Atom.to_string(key), value)
    end)
  end

  defp timezone() do
    Application.get_env(:forecaster, :timezone, "Europe/Berlin")
  end
end
