defmodule PvForecast.TrainingData do
  @moduledoc """
  Loads daily training data from a CSV file.

  The file is personal data (production of your own PV installation) and is
  kept out of git. Expected header and format:

      date,max_temp,sunshine_hours,rain_mm,pv_production
      2024-10-01,17.8,3.5,10.3,12.3

  Weather values come from a weather station near the installation,
  `pv_production` is the measured daily production in kWh.
  """

  @header "date,max_temp,sunshine_hours,rain_mm,pv_production"

  @doc "Returns the records of the CSV file at `path` (default: configured `:training_data_path`)."
  def daily_data(path \\ Application.fetch_env!(:pv_forecast, :training_data_path)) do
    [header | rows] =
      path
      |> File.read!()
      |> String.split(~r/\R/, trim: true)

    unless String.trim(header) == @header do
      raise ArgumentError, "unexpected header in #{path}, expected: #{@header}"
    end

    Enum.map(rows, &parse_row/1)
  end

  defp parse_row(row) do
    [date, max_temp, sunshine_hours, rain_mm, pv_production] =
      row |> String.split(",") |> Enum.map(&String.trim/1)

    %{
      date: Date.from_iso8601!(date),
      max_temp: to_float(max_temp),
      sunshine_hours: to_float(sunshine_hours),
      rain_mm: to_float(rain_mm),
      pv_production: to_float(pv_production)
    }
  end

  defp to_float(value) do
    {number, ""} = Float.parse(value)
    number
  end
end
