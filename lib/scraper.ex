defmodule Forecaster.Scraper do
  @moduledoc """
  This module is GenServer responsible to get (scrap) the data from the weather website in fixed intervals.
  Reports are saved into an ETS table to give access to other processes.
  """
  use GenServer
  require Logger

  alias Forecaster.Weather

  # Client

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get_forecast(day :: integer()) :: {day :: integer(), map()} | nil
  def get_forecast(day) do
    :weather_report
    |> :ets.lookup(day)
    |> List.first()
  end

  # Server (callbacks)

  @impl true
  def init(_opts) do
    Logger.info("Starting Scraper")
    :ets.new(:weather_report, [:set, :protected, :named_table])
    Process.send_after(self(), :update, 1000)
    {:ok, nil}
  end

  @impl true
  def handle_info(:update, state) do
    Logger.info("Updating forecast from website")
    Process.send_after(self(), :update, update_interval())

    place()
    |> Weather.forecast()
    |> save()

    Logger.info("Forecast saved")
    {:noreply, state}
  end

  defp update_interval() do
    Application.get_env(:forecaster, :update_interval, :timer.hours(2))
  end

  defp place() do
    Application.get_env(:forecaster, :place)
  end

  defp save(report) do
    Enum.each(report, fn {day, forecast} ->
      :ets.insert(:weather_report, {day, forecast})
    end)
  end
end
