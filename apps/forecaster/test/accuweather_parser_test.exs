defmodule AccuweatherParserTest do
  use ExUnit.Case
  alias Forecaster.Backends.AccuweatherParser

  test "extract_forecast/1 parses weather data from accuweather HTML" do
    html = File.read!("test/fixtures/accuweather.html")

    result = AccuweatherParser.extract_forecast({:ok, html})

    assert %{hour: hour_data} = result
    assert is_map(hour_data)
    assert %{brightness: "0", cloud_cover: "79"} = hour_data[2]
    assert %{brightness: "7", cloud_cover: "55"} = hour_data[10]
  end
end
