defmodule PvForecast.Utils do
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
end
