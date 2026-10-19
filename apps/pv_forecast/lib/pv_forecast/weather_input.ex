defmodule PvForecast.WeatherInput do
  @moduledoc """
  Turns a scraped forecast day of the `:forecaster` app into a model input
  (`%{date:, max_temp:, sunshine_hours:, rain_mm:}`).

  Scraped values are strings. Rain is the sum of the hourly precipitation,
  as `precip_max` is the upper bound of a range ("2-5 mm") and would overstate
  rain compared to the measured totals the model was trained on.
  """

  alias PvForecast.Web.ForecastRequest

  @doc """
  Day 1 is `today`. Returns `{:ok, input}` or `{:error, reason}` when values
  are missing or outside the ranges the API accepts.
  """
  def from_forecast({day, forecast}, %Date{} = today) when is_integer(day) and is_map(forecast) do
    with {:ok, max_temp} <- number(forecast, :temp_max),
         {:ok, sunshine_hours} <- number(forecast, :sun),
         {:ok, rain_mm} <- rain(forecast),
         {:ok, [input]} <-
           ForecastRequest.parse(%{
             "date" => today |> Date.add(day - 1) |> Date.to_iso8601(),
             "max_temp" => max_temp,
             "sunshine_hours" => sunshine_hours,
             "rain_mm" => rain_mm
           }) do
      {:ok, input}
    else
      {:error, [_ | _] = errors} -> {:error, {:invalid, errors}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rain(%{hour: hours} = forecast) when map_size(hours) > 0 do
    hourly = for {_hour, %{precip: precip}} <- hours, do: parse(precip)

    if hourly != [] and Enum.all?(hourly, &match?({:ok, _}, &1)),
      do: {:ok, hourly |> Enum.map(fn {:ok, mm} -> mm end) |> Enum.sum()},
      else: number(forecast, :precip_max)
  end

  defp rain(forecast), do: number(forecast, :precip_max)

  defp number(forecast, key) do
    case forecast |> Map.get(key) |> parse() do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing, key}}
    end
  end

  defp parse(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.replace("−", "-")
      |> String.replace(",", ".")

    case Float.parse(normalized) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse(_value), do: :error
end
