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
    test_pid = self()

    model_server =
      start_supervised!({ModelServer, path: TestFixtures.ensemble_path(), name: nil}, id: :model)

    publisher_opts = [
      name: nil,
      model_server: model_server,
      forecasts_fn: fn -> @forecasts end,
      today_fn: fn -> @today end,
      publish_fn: fn day, key, value -> send(test_pid, {:published, day, key, value}) end
    ]

    %{model_server: model_server, publisher_opts: publisher_opts}
  end

  test "forecast/3 predicts all days with complete weather data", %{model_server: server} do
    capture_log(fn ->
      assert {:ok, [{1, day_1}, {2, _day_2}]} = Publisher.forecast(@forecasts, @today, server)
      assert day_1.pv_production_min <= day_1.pv_production
      assert day_1.pv_production <= day_1.pv_production_max
    end)
  end

  test "publishes the PV forecast under the day topic on weather updates", ctx do
    start_supervised!({Publisher, ctx.publisher_opts})

    capture_log(fn ->
      Forecaster.Events.broadcast(:forecast_updated)

      for day <- [1, 2], key <- [:pv_production, :pv_production_min, :pv_production_max] do
        assert_receive {:published, ^day, ^key, value} when is_float(value), 5_000
      end

      refute_received {:published, 3, _, _}
    end)
  end

  test "publishes nothing while the model is not ready", ctx do
    capture_log(fn ->
      server = start_supervised!({ModelServer, path: "tmp/test/nope.bin", name: nil}, id: :empty)
      start_supervised!({Publisher, Keyword.put(ctx.publisher_opts, :model_server, server)})

      Forecaster.Events.broadcast(:forecast_updated)
      refute_receive {:published, _, _, _}, 500
    end)
  end
end
