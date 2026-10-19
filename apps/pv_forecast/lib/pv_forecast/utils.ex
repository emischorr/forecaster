defmodule PvForecast.Utils do
  require Logger

  # Calculate solar declination angle from date or day of year
  def solar_declination(date) when is_struct(date, Date) do
    date
    |> Date.day_of_year()
    |> solar_declination()
  end

  def solar_declination(day_of_year) when is_number(day_of_year) do
    # declination = 23.45° × sin(360° × (284 + day_of_year) / 365)
    angle_rad = 2 * :math.pi() * (284 + day_of_year) / 365
    23.45 * :math.sin(angle_rad)
  end

  # Turn validation problems of a loaded model file into an error (strict)
  # or a logged warning (non-strict)
  def check_compatibility(_kind, [], _strict_validation), do: :ok

  def check_compatibility(kind, problems, true) do
    {:error, "Incompatible #{kind}: #{Enum.join(problems, "; ")}"}
  end

  def check_compatibility(kind, problems, false) do
    Logger.warning("Loading incompatible #{kind} anyway: #{Enum.join(problems, "; ")}")
    :ok
  end
end
