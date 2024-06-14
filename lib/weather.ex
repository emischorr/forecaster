defmodule Forecaster.Weather do
  use Hound.Helpers

  defmodule Host do
    @callback base_url() :: String.t()
  end

  defmodule ProdHost do
    @behaviour Host
    def base_url, do: "https://www.meteoblue.com/weather/week/"
  end

  @doc """
  Returns a forecast for a given place.

  The forecast is structured as a list of tuples with the first element being the day, starting from 1,
  and the second element being a map of forcasted properties.

  ## Example
    iex> Forecaster.Weather.forecast("a_place_1234567")
    [
      {1, %{temp_max: "27", temp_min: "16", precip_max: "0", sun: "12", uv: "7"}},
      {2, %{temp_max: "28", temp_min: "11", precip_max: "0", sun: "13", uv: "6"}},
      {3, %{temp_max: "28", temp_min: "12", precip_max: "0", sun: "13", uv: "6"}},
      {4, %{temp_max: "28", temp_min: "13", precip_max: "0", sun: "12", uv: "6"}},
      {5, %{temp_max: "29", temp_min: "15", precip_max: "0", sun: "8", uv: "6"}},
      {6, %{temp_max: "30", temp_min: "16", precip_max: "0", sun: "8", uv: "6"}},
      {7, %{temp_max: "31", temp_min: "17", precip_max: "0", sun: "10", uv: "6"}}
    ]
  """
  @spec forecast(String.t()) :: list({number(), map()})
  def forecast(place) do
    place |> url_for() |> open()

    report = 1..7
    |> Enum.map(fn day -> {day, find_element(:id, "day#{day}")} end)
    |> Enum.map(&add_day_details/1)
    |> Enum.map(fn {day, element, detail} -> {day, collect(element, detail)} end)

    close()
    report
  end


  defp open(url) do
    Hound.start_session(user_agent: :firefox, browser: :firefox)
    # use a small smartphone viewport to be able to use click events to get further details for each day
    current_window_handle() |> set_window_size(600, 800)
    navigate_to(url)
    page_title() |> IO.inspect(label: "title")
    maybe_accept_cookies()
    # take_screenshot("debug/loading.png")
  end

  defp maybe_accept_cookies do
    case search_element(:id, "gdpr_form") do
      {:ok, element} ->
        find_within_element(element, :xpath, ~s|//input[@type='submit']|)
        |> click()
      {:error, _error} -> nil
    end
  end

  defp close(), do: Hound.end_session

  defp url_for(loc_id), do: "#{host().base_url}#{loc_id}"
  defp url_for(loc_id, day), do: "#{host().base_url}#{loc_id}?day=#{day}"

  defp add_day_details({day, day_element}) do
    day_element
    |> find_within_element(:xpath, ~s|//a[@data-mobile and @data-day='#{day}']|)
    |> click()

    {day, day_element, detail_element_for(day_element)}
  end

  defp detail_element_for(day_element) do
    day = day_element |> attribute_value("id") |> String.slice(-1,1)
    find_element(:xpath, ~s|//div[contains(@class, 'tab-detail') and @data-day='#{day}']|)
  end

  defp collect(day_element, detail_element) do
    %{
      temp_max: temp_max(day_element),
      temp_min: temp_min(day_element),
      precip_max: precipitation_max(day_element),
      sun: sunshine(day_element),
      uv: uv_index(detail_element)
    }
  end

  defp temp_max(day_element) do
    find_within_element(day_element, :class, "tab-temp-max")
    |> inner_text()
    |> String.replace(" °C", "")
    |> String.trim
  end

  defp temp_min(day_element) do
    find_within_element(day_element, :class, "tab-temp-min")
    |> inner_text()
    |> String.replace(" °C", "")
    |> String.trim
  end

  defp precipitation_max(day_element) do
    find_within_element(day_element, :class, "tab-precip")
    |> inner_text()
    |> String.replace(" mm", "")
    |> String.trim
    |> max_value()
  end

  defp sunshine(day_element) do
    find_within_element(day_element, :class, "tab-sun")
    |> inner_text()
    |> String.replace(" h", "")
    |> String.trim
  end

  defp uv_index(detail_element) do
    find_within_element(detail_element, :class, "uv-index")
    |> inner_text()
    |> String.replace("UV ", "")
    |> String.trim
  end

  defp max_value(value) when is_binary(value) do
    case value do
      "-" -> "0"
      min_max -> String.split(min_max, ~r|.-|) |> List.last()
    end
  end

  defp host, do: Application.get_env(:forecaster, :weather_host_impl, ProdHost)
end
