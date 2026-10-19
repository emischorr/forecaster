defmodule PvForecast.PublisherTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PvForecast.ModelServer
  alias PvForecast.Publisher
  alias PvForecast.TestFixtures

  @today ~D[2026-10-19]
  @forecasts [
    {1, %{temp_max: "14", sun: "1", precip_max: "5", hour: %{0 => %{precip: "0.5"}}}},
    {2, %{temp_max: "18", sun: "8", precip_max: "0"}},
    # Incomplete scrape, skipped
    {3, %{temp_max: "", sun: "3", precip_max: "0"}}
  ]

  setup do
    model_server =
      start_supervised!({ModelServer, path: TestFixtures.ensemble_path(), name: nil}, id: :model)

    # The MQTT connection is disabled in tests, so the test receives the publish casts.
    Process.register(self(), MQTT.Connection)

    %{model_server: model_server, publisher_opts: [name: nil, model_server: model_server]}
  end

  test "forecast/3 predicts all days with complete weather data", %{model_server: server} do
    capture_log(fn ->
      assert {:ok, [{1, day_1}, {2, _day_2}]} = Publisher.forecast(@forecasts, @today, server)
      assert day_1.pv_production_min <= day_1.pv_production
      assert day_1.pv_production <= day_1.pv_production_max
    end)
  end

  test "publishes the PV forecast under the day topic on weather updates", ctx do
    publisher = start_supervised!({Publisher, ctx.publisher_opts})

    capture_log(fn ->
      send(publisher, {Forecaster, :forecast_updated, @forecasts})

      for day <- [1, 2], key <- ["pv_production", "pv_production_min", "pv_production_max"] do
        subtopic = "#{day}/#{key}"
        assert_receive {:"$gen_cast", {:publish, ^subtopic, value}}, 5_000
        assert {_, ""} = Float.parse(value)
      end

      refute_received {:"$gen_cast", {:publish, "3/" <> _, _}}
    end)
  end

  test "publishes nothing while the model is not ready", ctx do
    capture_log(fn ->
      server = start_supervised!({ModelServer, path: "tmp/test/nope.bin", name: nil}, id: :empty)

      publisher =
        start_supervised!({Publisher, Keyword.put(ctx.publisher_opts, :model_server, server)})

      send(publisher, {Forecaster, :forecast_updated, @forecasts})
      refute_receive {:"$gen_cast", {:publish, _, _}}, 500
    end)
  end
end
