defmodule PvForecast.Web.Router do
  @moduledoc """
  HTTP API for daily PV production forecasts.

    * `POST /api/v1/forecast` - forecast for one or more days (see `PvForecast.Web.ForecastRequest`)
    * `GET  /api/v1/model`    - metadata of the loaded model
    * `GET  /health`          - 200 when a model is loaded, 503 otherwise
  """

  use Plug.Router
  use Plug.ErrorHandler

  alias PvForecast.Model
  alias PvForecast.ModelServer
  alias PvForecast.Web.ForecastRequest

  @features [
    %{name: "max_temp", unit: "°C", description: "Daily maximum temperature"},
    %{name: "sunshine_hours", unit: "h", description: "Daily sunshine duration"},
    %{name: "rain_mm", unit: "mm", description: "Daily precipitation"}
  ]

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: [], json_decoder: Jason)
  plug(:dispatch)

  post "/api/v1/forecast" do
    with {:ok, days} <- ForecastRequest.parse(conn.body_params),
         inputs = days |> Enum.map(&Model.features/1) |> Nx.tensor(type: :f32),
         {:ok, prediction} <- ModelServer.predict(inputs, model_server(conn)) do
      %{metadata: metadata} = ModelServer.info(model_server(conn))

      forecasts =
        [days, prediction.mean, prediction.min, prediction.max]
        |> Enum.zip_with(fn [day, mean, min, max] ->
          %{
            date: day.date,
            energy_kwh: Float.round(mean, 2),
            min_kwh: Float.round(min, 2),
            max_kwh: Float.round(max, 2)
          }
        end)

      json(conn, 200, %{
        model_version: metadata.version,
        model_created_at: metadata.created_at,
        unit: "kWh",
        forecasts: forecasts
      })
    else
      {:error, :not_ready} ->
        json(conn, 503, %{error: "model_not_ready"})

      {:error, errors} ->
        json(conn, 422, %{error: "invalid_request", details: errors})
    end
  end

  get "/api/v1/model" do
    case ModelServer.info(model_server(conn)) do
      %{status: :ready, metadata: metadata, loaded_at: loaded_at} ->
        json(conn, 200, %{
          status: "ready",
          version: metadata.version,
          description: Map.get(metadata, :description),
          created_at: metadata.created_at,
          loaded_at: loaded_at,
          ensemble_size: metadata.ensemble_size,
          training_samples: metadata.training_samples,
          validation_samples: Map.get(metadata, :validation_samples),
          metrics: Map.get(metadata, :metrics),
          target: %{name: "pv_production", unit: "kWh", resolution: "daily"},
          features: @features,
          max_days_per_request: ForecastRequest.max_days()
        })

      %{status: :not_ready} ->
        json(conn, 503, %{status: "not_ready"})
    end
  end

  get "/health" do
    case ModelServer.info(model_server(conn)) do
      %{status: :ready} -> json(conn, 200, %{status: "ok", model: "ready"})
      %{status: :not_ready} -> json(conn, 503, %{status: "degraded", model: "not_ready"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{reason: reason}) do
    message =
      case reason do
        %Plug.Parsers.ParseError{} -> "invalid_json"
        %Plug.Parsers.UnsupportedMediaTypeError{} -> "unsupported_media_type"
        _ -> "internal_error"
      end

    json(conn, conn.status, %{error: message})
  end

  # Tests point the router at their own model server via conn.private
  defp model_server(conn), do: Map.get(conn.private, :model_server, ModelServer)

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
