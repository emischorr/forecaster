defmodule PvForecast.Web.RouterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test

  alias PvForecast.ModelServer
  alias PvForecast.TestFixtures
  alias PvForecast.Web.Router

  setup do
    server = start_supervised!({ModelServer, path: TestFixtures.ensemble_path(), name: nil})
    %{server: server}
  end

  defp call(server, method, path, body \\ nil) do
    method
    |> conn(path, body && Jason.encode!(body))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_private(:model_server, server)
    |> Router.call(Router.init([]))
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  @day %{"date" => "2026-06-21", "max_temp" => 27, "sunshine_hours" => 12, "rain_mm" => 0}

  test "forecast for a single day", %{server: server} do
    conn = call(server, :post, "/api/v1/forecast", @day)

    assert conn.status == 200
    assert %{"unit" => "kWh", "forecasts" => [forecast]} = json_body(conn)

    assert %{"date" => "2026-06-21", "energy_kwh" => kwh, "min_kwh" => min, "max_kwh" => max} =
             forecast

    assert min <= kwh and kwh <= max
  end

  test "forecast for several days keeps order", %{server: server} do
    days = [@day, %{@day | "date" => "2026-12-21", "sunshine_hours" => 0.5}]
    conn = call(server, :post, "/api/v1/forecast", %{"days" => days})

    assert conn.status == 200
    assert ["2026-06-21", "2026-12-21"] = Enum.map(json_body(conn)["forecasts"], & &1["date"])
  end

  test "bare JSON array of days", %{server: server} do
    conn = call(server, :post, "/api/v1/forecast", [@day, @day])

    assert conn.status == 200
    assert length(json_body(conn)["forecasts"]) == 2
  end

  test "invalid fields return 422 with details", %{server: server} do
    day = %{"date" => "21.06.2026", "max_temp" => "warm", "sunshine_hours" => 30}
    conn = call(server, :post, "/api/v1/forecast", %{"days" => [day]})

    assert conn.status == 422
    fields = json_body(conn)["details"] |> Enum.map(& &1["field"]) |> Enum.sort()
    assert fields == ["date", "max_temp", "rain_mm", "sunshine_hours"]
  end

  test "too many days return 422", %{server: server} do
    conn = call(server, :post, "/api/v1/forecast", %{"days" => List.duplicate(@day, 32)})

    assert conn.status == 422
  end

  test "malformed JSON returns 400", %{server: server} do
    conn =
      conn(:post, "/api/v1/forecast", "{not json")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_private(:model_server, server)

    # Plug.ErrorHandler sends the response, then re-raises
    assert_raise Plug.Parsers.ParseError, fn -> Router.call(conn, Router.init([])) end
    assert_received {_ref, {400, _headers, body}}
    assert Jason.decode!(body) == %{"error" => "invalid_json"}
  end

  test "model info and health", %{server: server} do
    conn = call(server, :get, "/api/v1/model")
    assert conn.status == 200
    assert %{"status" => "ready", "ensemble_size" => 3, "features" => [_, _, _]} = json_body(conn)

    assert call(server, :get, "/health").status == 200
  end

  test "503 when no model is loaded" do
    capture_log(fn ->
      server =
        start_supervised!({ModelServer, path: "tmp/test/nope.bin", name: :empty_server},
          id: :empty
        )

      assert call(server, :post, "/api/v1/forecast", @day).status == 503
      assert call(server, :get, "/health").status == 503
      assert call(server, :get, "/api/v1/model").status == 503
    end)
  end

  test "unknown routes return 404", %{server: server} do
    assert call(server, :get, "/nope").status == 404
  end
end
