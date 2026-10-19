defmodule Forecaster.Scraper do
  @moduledoc """
  This module is GenServer responsible to get (scrap) the data from the weather website in fixed intervals.
  Reports are saved into an ETS table to give access to other processes.
  """
  use GenServer
  require Logger

  alias Forecaster.Weather

  # Client

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get_forecast(day :: integer()) :: {day :: integer(), map()} | nil
  def get_forecast(day) do
    :weather_report
    |> :ets.lookup(day)
    |> List.first()
  end

  def update, do: GenServer.cast(__MODULE__, :update)

  # Server (callbacks)

  @impl true
  def init(_opts) do
    Logger.info("Starting Scraper")
    :ets.new(:weather_report, [:set, :protected, :named_table])
    Process.send_after(self(), :update, 1000)
    {:ok, nil}
  end

  @impl true
  def handle_info(:update, state) do
    Process.send_after(self(), :update, update_interval())
    do_update()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:update, state) do
    do_update()
    {:noreply, state}
  end

  defp do_update do
    Logger.info("Updating forecast from website")
    accu = Weather.forecast(accu_place())

    meteo_place()
    |> Weather.forecast()
    |> merge_forecast(accu)
    |> save()

    Logger.info("Forecast saved")
  end

  defp merge_forecast(fc_one, fc_two) do
    Enum.map(fc_one, fn {day, predictions_one} ->
      predictions = merge_day_predictions(predictions_one, day_from_forecast(fc_two, day))

      {day, predictions}
    end)
  end

  # find the matching day from the forecast or return an empty map to easily merge it
  defp day_from_forecast(forecast, target_day) when is_list(forecast) do
    Enum.find_value(forecast, fn {day, predictions} ->
      if day == target_day, do: predictions
    end) || %{}
  end

  defp merge_day_predictions(predictions_1, predictions_2)
       when is_map(predictions_1) and is_map(predictions_2) do
    Map.merge(predictions_1, predictions_2, fn
      :hour, v1, v2 ->
        Map.merge(v1, v2, fn _key, hour_map_1, hour_map_2 ->
          Map.merge(hour_map_1, hour_map_2)
        end)

      _key, v1, v2 ->
        v2
    end)
  end

  defp save(report) do
    Enum.each(report, fn
      {1, forecast} ->
        # for today we have to look up the forecast we already have stored first not completely override it
        # as accuweather only shows FUTURE hours and not current hour.
        # We can savely merge it though as accuweather only gives us FUTURE hours ;-)
        updated_forecast =
          :weather_report
          |> :ets.lookup(1)
          |> List.first({1, %{}})
          |> elem(1)
          |> merge_day_predictions(forecast)

        if length(Map.keys(updated_forecast)) > 0,
          do: :ets.insert(:weather_report, {1, updated_forecast})

      {day, forecast} ->
        if length(Map.keys(forecast)) > 0, do: :ets.insert(:weather_report, {day, forecast})
    end)
  end

  defp update_interval() do
    Application.get_env(:forecaster, :update_interval, :timer.hours(2))
  end

  defp meteo_place() do
    Application.get_env(:forecaster, :meteo) |> Keyword.get(:place, "berlin_germany_2950159")
  end

  defp accu_place() do
    [country: country, place_name: loc_name, place_id: loc_id] =
      Application.get_env(:forecaster, :accuweather)

    {country, loc_name, loc_id}
  end
end
