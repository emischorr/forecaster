defmodule Forecaster.Publisher do
  @moduledoc """
  GenServer to publish the updated forecast for days as well as an hourly "measurement" to the MQTT broker.
  Daily forecasts get published in configured interval,
  while the forecast for the current hour is published every hour as a sort of measurement.

  The module sends also meta data to the MQTT broker on startup.
  """
  use GenServer
  require Logger

  alias Forecaster.MQTT
  alias Forecaster.Scraper
  alias Forecaster.Weather

  # Client

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def publish_current_hour do
    GenServer.cast(__MODULE__, :publish_current_hour)
  end

  # Server (callbacks)

  @impl true
  def init(_opts) do
    Logger.info("Starting Publisher")
    {:ok, %{forecast_retry: false}, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    {:ok, mqtt_client} = MQTT.connect()
    MQTT.publish_meta(mqtt_client)
    # Wait 30s to do the first publish
    Process.send_after(self(), :publish, 30_000)
    {:noreply, Map.put(state, :mqtt_client, mqtt_client)}
  end

  @impl true
  def handle_cast(:publish_current_hour, state) do
    Logger.info("Publishing current forecast measurement")

    %Time{hour: hour} = Time.utc_now()

    case Scraper.get_forecast(1) do
      {1, %{hour: %{^hour => forecast}}} ->
        publish_current_hour(forecast, state.mqtt_client)
        {:noreply, %{state | forecast_retry: false}}

      nil ->
        unless state.forecast_retry,
          do: Process.send_after(self(), :publish_current_hour, 60_000)

        {:noreply, %{state | forecast_retry: true}}
    end
  end

  @impl true
  def handle_info(:publish, state) do
    Logger.info("Publishing daily forecast")
    Process.send_after(self(), :publish, update_interval())

    Weather.forecast_range()
    |> Enum.map(&Scraper.get_forecast(&1))
    |> Enum.each(fn {day, forecast} ->
      publish_daily_forecast(forecast, day, state.mqtt_client)
    end)

    {:noreply, state}
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

  defp update_interval() do
    Application.get_env(:forecaster, :update_interval, :timer.hours(2))
  end
end
