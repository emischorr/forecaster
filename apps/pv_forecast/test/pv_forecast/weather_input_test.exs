defmodule PvForecast.WeatherInputTest do
  use ExUnit.Case, async: true

  alias Forecaster.Backends.MeteoParser
  alias PvForecast.WeatherInput

  @today ~D[2026-10-19]

  test "builds the model input from a scraped meteo day" do
    forecast =
      MeteoParser.extract_forecast({:ok, File.read!("../forecaster/test/fixtures/meteo.html")})

    assert {:ok, input} = WeatherInput.from_forecast({1, forecast}, @today)
    assert input.date == @today
    assert input.max_temp == 14.0
    assert input.sunshine_hours == 1.0
    # Sum of the hourly values, not the upper bound of precip_max ("5")
    assert_in_delta input.rain_mm, 2.3, 0.001
  end

  test "maps the day number to a date" do
    assert {:ok, %{date: ~D[2026-10-21]}} =
             WeatherInput.from_forecast({3, %{temp_max: "9", sun: "0", precip_max: "0"}}, @today)
  end

  test "falls back to precip_max without hourly precipitation" do
    forecast = %{temp_max: "-2", sun: "6,5", precip_max: "1", hour: %{3 => %{cloud_cover: "10"}}}

    assert {:ok, %{max_temp: -2.0, sunshine_hours: 6.5, rain_mm: 1.0}} =
             WeatherInput.from_forecast({1, forecast}, @today)
  end

  test "rejects days with missing or implausible values" do
    assert {:error, {:missing, :sun}} =
             WeatherInput.from_forecast({1, %{temp_max: "14", sun: "", precip_max: "0"}}, @today)

    assert {:error, {:invalid, [%{field: "sunshine_hours"}]}} =
             WeatherInput.from_forecast(
               {1, %{temp_max: "14", sun: "20", precip_max: "0"}},
               @today
             )
  end
end
