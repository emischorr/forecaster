defmodule Forecaster.Weather do
  @doc """
  Returns a forecast for a given place.

  The forecast is structured as a list of tuples with the first element being the day, starting from 1 (today),
  and the second element being a map of forcasted properties.
  """
  @spec forecast(String.t()) :: list({integer(), map()})
  defdelegate forecast(place), to: Forecaster.Backends.Meteo

  @spec forecast_range :: Range.t()
  defdelegate forecast_range, to: Forecaster.Backends.Meteo
end
