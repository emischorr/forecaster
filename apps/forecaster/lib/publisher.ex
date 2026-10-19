defmodule Forecaster.Publisher do
  @moduledoc """
  GenServer to publish the updated forecast for days as well as an hourly "measurement" to the MQTT broker.
  Daily forecasts get published whenever the scraper broadcasts a `:forecast_updated` event,
  while the forecast for the current hour is published every hour as a sort of measurement.
  """
  use GenServer
  require Logger

  alias Forecaster.Events
  alias Forecaster.Scraper

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
    Events.subscribe(:forecast_updated)
    {:ok, %{forecast_retry: false}}
  end

  @impl true
  def handle_cast(:publish_current_hour, state) do
    Logger.info("Publishing current forecast measurement")

    hour = timezone() |> DateTime.now!() |> Map.get(:hour)

    case Scraper.get_forecast(1) do
      {1, %{hour: %{^hour => forecast}}} ->
        publish_current_hour(forecast)
        {:noreply, %{state | forecast_retry: false}}

      _else ->
        unless state.forecast_retry,
          do: Process.send_after(self(), :retry_current_hour, 60_000)

        {:noreply, %{state | forecast_retry: true}}
    end
  end

  @impl true
  def handle_info({Forecaster, :forecast_updated, forecasts}, state) do
    Logger.info("Publishing daily forecast")

    Enum.each(forecasts, fn {day, forecast} ->
      publish_daily_forecast(forecast, day)
    end)

    {:noreply, state}
  end

  def handle_info(:retry_current_hour, state) do
    handle_cast(:publish_current_hour, state)
  end

  defp publish_daily_forecast(forecast, day) do
    forecast
    |> Map.drop([:hour])
    |> Enum.each(fn {key, value} -> MQTT.publish("#{day}/#{key}", value) end)
  end

  defp publish_current_hour(forecast) do
    Enum.each(forecast, fn {key, value} -> MQTT.publish("current_hour/#{key}", value) end)
  end

  defp timezone() do
    Application.get_env(:forecaster, :timezone, "Europe/Berlin")
  end
end
