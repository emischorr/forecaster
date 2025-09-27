defmodule MeteoParserTest do
  use ExUnit.Case
  alias Forecaster.Backends.MeteoParser

  test "extract_forecast/1 parses weather data from HTML" do
    html = File.read!("test/fixtures/weather.html")

    result = MeteoParser.extract_forecast({:ok, html})

    assert %{
             temp_max: "14",
             temp_min: "10",
             precip_max: "5",
             sun: "1",
             uv: "2",
             hour: hour_data
           } = result

    assert is_map(hour_data)

    assert %{
             temperature: "11",
             precip: "0.5",
             precip_prop: "65",
             humidity: "97",
             condition: "Overcast with light rain"
           } = hour_data[2]

    assert %{
             temperature: "12",
             precip: "0",
             precip_prop: "14",
             humidity: "96",
             condition: "Overcast"
           } = hour_data[10]
  end
end
