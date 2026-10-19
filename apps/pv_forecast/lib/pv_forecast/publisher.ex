defmodule PvForecast.Publisher do
  @moduledoc """
  Publishes the PV production forecast next to the weather forecast.

  Subscribes to the `:forecast_updated` event of the `:forecaster` app. On every
  weather update it predicts the daily production for all days with weather data
  and publishes it under the same day topic as the weather:

      <namespace>/<day>/pv_production       ensemble mean in kWh
      <namespace>/<day>/pv_production_min   lowest member prediction
      <namespace>/<day>/pv_production_max   highest member prediction

  Days with incomplete weather data are skipped. Nothing is published while the
  model is not ready.
  """

  use GenServer
  require Logger

  alias Forecaster.Events
  alias PvForecast.Model
  alias PvForecast.ModelServer
  alias PvForecast.WeatherInput

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Predicts the production for scraped `forecasts` (`[{day, forecast}]`), day 1 being `today`.

  Returns `{:ok, [{day, %{pv_production: kwh, pv_production_min: kwh, pv_production_max: kwh}}]}`.
  """
  def forecast(forecasts, %Date{} = today, model_server \\ ModelServer) do
    inputs =
      Enum.flat_map(forecasts, fn {day, _} = forecast ->
        case WeatherInput.from_forecast(forecast, today) do
          {:ok, input} ->
            [{day, input}]

          {:error, reason} ->
            Logger.warning("Skipping PV forecast for day #{day}: #{inspect(reason)}")
            []
        end
      end)

    predict(inputs, model_server)
  end

  defp predict([], _model_server), do: {:ok, []}

  defp predict(inputs, model_server) do
    {days, inputs} = Enum.unzip(inputs)
    tensor = inputs |> Enum.map(&Model.features/1) |> Nx.tensor(type: :f32)

    with {:ok, %{mean: mean, min: min, max: max}} <- ModelServer.predict(tensor, model_server) do
      {:ok,
       Enum.zip_with([days, mean, min, max], fn [day, mean, min, max] ->
         {day,
          %{
            pv_production: Float.round(mean, 1),
            pv_production_min: Float.round(min, 1),
            pv_production_max: Float.round(max, 1)
          }}
       end)}
    end
  end

  # Server (callbacks)

  @impl true
  def init(opts) do
    Events.subscribe(:forecast_updated)

    {:ok,
     %{
       model_server: Keyword.get(opts, :model_server, ModelServer),
       forecasts_fn: Keyword.get(opts, :forecasts_fn, &Forecaster.Scraper.get_forecasts/0),
       publish_fn: Keyword.get(opts, :publish_fn, &Forecaster.Publisher.publish_daily/3),
       today_fn: Keyword.get(opts, :today_fn, &today/0)
     }}
  end

  @impl true
  def handle_info({Events, :forecast_updated}, state) do
    case forecast(state.forecasts_fn.(), state.today_fn.(), state.model_server) do
      {:ok, predictions} ->
        Logger.info("Publishing PV forecast for #{length(predictions)} days")

        for {day, values} <- predictions, {key, value} <- values do
          state.publish_fn.(day, key, value)
        end

      {:error, reason} ->
        Logger.warning("No PV forecast published: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp today do
    :forecaster
    |> Application.get_env(:timezone, "Europe/Berlin")
    |> DateTime.now!()
    |> DateTime.to_date()
  end
end
