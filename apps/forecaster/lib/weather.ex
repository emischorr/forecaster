defmodule Forecaster.Weather do
  @doc """
  Returns a forecast for a given place.

  The forecast is structured as a list of tuples with the first element being the day, starting from 1 (today),
  and the second element being a map of forcasted properties.
  """

  alias Forecaster.Backends.Meteo
  alias Forecaster.Backends.Accuweather

  @spec forecast(String.t()) :: list({integer(), map()})
  def forecast(place) when is_binary(place), do: Meteo.forecast(place)

  @spec forecast({String.t(), String.t(), String.t()}) :: list({integer(), map()})
  def forecast(place) when is_tuple(place), do: Accuweather.forecast(place)

  @spec forecast_range(atom()) :: Range.t()
  def forecast_range(:meteo), do: Meteo.forecast_range()
  def forecast_range(:accuweather), do: Accuweather.forecast_range()
end
