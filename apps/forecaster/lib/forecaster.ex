defmodule Forecaster do
  @moduledoc """
  Public API of the `:forecaster` app for other umbrella apps.
  """

  @doc """
  Subscribes the calling process to forecast updates.

  After every scrape the subscriber receives `{Forecaster, :forecast_updated, forecasts}`,
  where `forecasts` is a list of `{day, forecast}` sorted by day, day 1 being today.
  """
  defdelegate subscribe, to: Forecaster.Events, as: :subscribe_forecast_updated
end
