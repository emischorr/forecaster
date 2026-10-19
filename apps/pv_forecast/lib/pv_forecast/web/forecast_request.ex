defmodule PvForecast.Web.ForecastRequest do
  @moduledoc """
  Validates the JSON body of a forecast request.

  Accepts either `{"days": [day, ...]}`, a bare JSON array of days, or a
  single day object, where a day is
  `{"date": "2026-10-20", "max_temp": 14.2, "sunshine_hours": 5.5, "rain_mm": 0.0}`.
  """

  @max_days 31

  # {json field, key, min, max}: plausible ranges for daily weather values
  @numeric_fields [
    {"max_temp", :max_temp, -30.0, 45.0},
    {"sunshine_hours", :sunshine_hours, 0.0, 16.0},
    {"rain_mm", :rain_mm, 0.0, 300.0}
  ]

  def max_days, do: @max_days

  @doc """
  Returns `{:ok, days}` with atom-keyed day maps, or `{:error, errors}` with a
  list of `%{index:, field:, message:}` maps.
  """
  def parse(%{"days" => days}) when is_list(days), do: parse_days(days)
  def parse(%{"days" => _}), do: {:error, [error(nil, "days", "must be a list")]}
  def parse(%{"_json" => days}) when is_list(days), do: parse_days(days)
  def parse(%{} = day), do: parse_days([day])

  defp parse_days([]), do: {:error, [error(nil, "days", "must not be empty")]}

  defp parse_days(days) when length(days) > @max_days do
    {:error, [error(nil, "days", "at most #{@max_days} days per request")]}
  end

  defp parse_days(days) do
    results = days |> Enum.with_index() |> Enum.map(fn {day, index} -> parse_day(day, index) end)

    case Enum.flat_map(results, fn {_day, errors} -> errors end) do
      [] -> {:ok, Enum.map(results, fn {day, []} -> day end)}
      errors -> {:error, errors}
    end
  end

  defp parse_day(%{} = day, index) do
    {date, date_errors} = parse_date(Map.get(day, "date"), index)

    {values, value_errors} =
      Enum.reduce(@numeric_fields, {%{}, []}, fn {field, key, min, max}, {values, errors} ->
        case parse_number(Map.get(day, field), min, max) do
          {:ok, value} -> {Map.put(values, key, value), errors}
          {:error, message} -> {values, errors ++ [error(index, field, message)]}
        end
      end)

    {Map.put(values, :date, date), date_errors ++ value_errors}
  end

  defp parse_day(_day, index), do: {nil, [error(index, nil, "must be an object")]}

  defp parse_date(value, index) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {date, []}
      {:error, _} -> {nil, [error(index, "date", "must be an ISO 8601 date (YYYY-MM-DD)")]}
    end
  end

  defp parse_date(nil, index), do: {nil, [error(index, "date", "is required")]}

  defp parse_date(_value, index),
    do: {nil, [error(index, "date", "must be an ISO 8601 date (YYYY-MM-DD)")]}

  defp parse_number(nil, _min, _max), do: {:error, "is required"}

  defp parse_number(value, min, max) when is_number(value) do
    if value >= min and value <= max,
      do: {:ok, value / 1},
      else: {:error, "must be between #{min} and #{max}"}
  end

  defp parse_number(_value, _min, _max), do: {:error, "must be a number"}

  defp error(index, field, message), do: %{index: index, field: field, message: message}
end
