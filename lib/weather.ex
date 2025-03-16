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

  The forecast is structured as a list of tuples with the first element being the day, starting from 1 (today),
  and the second element being a map of forcasted properties.

  ## Example
    iex> Forecaster.Weather.forecast("a_place_1234567")
    [
      {1, %{temp_max: "27", temp_min: "16", precip_max: "0", sun: "12", uv: "7"},
            hour: %{
              1 => %{temperature: "4", condition: "Mostly cloudy"},
              2 => %{temperature: "4", condition: "Mostly cloudy"},
              3 => %{temperature: "4", condition: "Mostly cloudy"},
              4 => %{temperature: "4", condition: "Overcast with light rain"},
              5 => %{temperature: "3", condition: "Partly cloudy"},
              6 => %{temperature: "3", condition: "Partly cloudy"},
              7 => %{temperature: "4", condition: "Clear with few low clouds"},
              8 => %{temperature: "5", condition: "Clear with few low clouds"},
              9 => %{temperature: "6", condition: "Clear with few low clouds"},
              10 => %{temperature: "8", condition: "Clear with few low clouds"},
              11 => %{temperature: "9", condition: "Clear with few low clouds"},
              12 => %{temperature: "9", condition: "Partly cloudy"},
              13 => %{temperature: "9", condition: "Partly cloudy"},
              14 => %{temperature: "9", condition: "Mixed with showers"},
              15 => %{temperature: "8", condition: "Partly cloudy"},
              16 => %{temperature: "8", condition: "Partly cloudy"},
              17 => %{temperature: "7", condition: "Partly cloudy"},
              18 => %{temperature: "6", condition: "Partly cloudy"},
              19 => %{temperature: "6", condition: "Partly cloudy"},
              20 => %{temperature: "5", condition: "Partly cloudy"},
              21 => %{temperature: "5", condition: "Clear with few low clouds"},
              22 => %{temperature: "4", condition: "Clear with few low clouds"},
              23 => %{temperature: "4", condition: "Clear with few low clouds"},
              24 => %{temperature: "3", condition: "Partly cloudy"}
            }
      },
      {2, %{temp_max: "28", temp_min: "11", precip_max: "0", sun: "13", uv: "6"}},
      ...
    ]
  """
  @spec forecast(String.t()) :: list({number(), map()})
  def forecast(place) do
    place |> url_for() |> open()

    find_element(:id, "day1")
    |> find_within_element(:xpath, ~s|//a[@data-mobile and @data-day='1']|)
    |> scroll_to()
    |> click()

    # switch to 1 hour view
    find_element(:class, "additional-parameters-toggle")
    |> scroll_to()
    |> click()

    report =
      forecast_range()
      |> Enum.map(fn day -> {day, find_element(:id, "day#{day}")} end)
      |> Enum.map(&add_day_details/1)
      |> Enum.map(fn {day, element, detail} -> {day, collect(element, detail)} end)

    close()
    report
  end

  def forecast_range(), do: 1..7

  defp open(url) do
    Hound.start_session(browser: :firefox)

    # use a small smartphone viewport to be able to use click events to get further details for each day
    current_window_handle() |> set_window_size(450, 900)
    navigate_to(url)
    page_title() |> IO.inspect(label: "title")
    maybe_accept_cookies()

    # Cookie would save the click but it's somehow not working
    # set_cookie(%{name: "extendedview", value: "true", secure: true})
    # take_screenshot("debug/loading.png")
  end

  defp maybe_accept_cookies do
    case search_element(:id, "gdpr_form") do
      {:ok, element} ->
        find_within_element(element, :xpath, ~s|//input[@type='submit']|)
        |> click()

      {:error, _error} ->
        nil
    end
  end

  defp close(), do: Hound.end_session()

  defp url_for(loc_id), do: "#{host().base_url()}#{loc_id}"
  # defp url_for(loc_id, day), do: "#{host().base_url}#{loc_id}?day=#{day}"

  defp scroll_to(element) do
    {width, height} = element_location(element)
    execute_script("window.scrollTo(#{width},#{height});")
    # apparently it takes some time to scroll
    Process.sleep(1000)
    element
  end

  defp add_day_details({day, day_element}) do
    day_element
    |> find_within_element(:xpath, ~s|//a[@data-mobile and @data-day='#{day}']|)
    |> scroll_to()
    |> click()

    {day, day_element, detail_element_for(day_element)}
  end

  defp detail_element_for(day_element) do
    day = day_element |> attribute_value("id") |> String.slice(-1, 1)
    find_element(:xpath, ~s|//div[contains(@class, 'tab-detail') and @data-day='#{day}']|)
  end

  defp collect(day_element, detail_element) do
    %{
      temp_max: temp_max(day_element),
      temp_min: temp_min(day_element),
      precip_max: precipitation_max(day_element),
      sun: sunshine(day_element),
      uv: uv_index(detail_element),
      hour: hourly_data(detail_element)
    }
  end

  defp temp_max(day_element) do
    find_within_element(day_element, :class, "tab-temp-max")
    |> inner_text()
    |> String.replace(" °C", "")
    |> String.trim()
  end

  defp temp_min(day_element) do
    find_within_element(day_element, :class, "tab-temp-min")
    |> inner_text()
    |> String.replace(" °C", "")
    |> String.trim()
  end

  defp precipitation_max(day_element) do
    find_within_element(day_element, :class, "tab-precip")
    |> inner_text()
    |> String.replace(" mm", "")
    |> String.trim()
    |> max_value()
  end

  defp sunshine(day_element) do
    find_within_element(day_element, :class, "tab-sun")
    |> inner_text()
    |> String.replace(" h", "")
    |> String.trim()
  end

  defp uv_index(detail_element) do
    find_within_element(detail_element, :class, "uv-index")
    |> inner_text()
    |> String.replace("UV ", "")
    |> String.trim()
  end

  defp max_value(value) when is_binary(value) do
    case value do
      "-" -> "0"
      min_max -> String.split(min_max, ~r|.-|) |> List.last()
    end
  end

  defp hourly_data(detail_element) do
    temps =
      detail_element
      |> find_within_element(:class, "temperatures")
      |> find_all_within_element(:xpath, ~s|td/div[contains(@class, 'cell')]|)
      |> Enum.map(fn e ->
        e
        |> inner_text()
        |> String.replace("°", "")
        |> String.trim()
      end)
      |> build_hourly_map(:temperature)

    conditions =
      detail_element
      |> find_all_within_element(:class, "picon")
      # find_all_elements(:class, "picon1h")
      |> Enum.map(&attribute_value(&1, "title"))
      |> build_hourly_map(:condition)

    Map.merge(temps, conditions, fn _key, v1, v2 -> Map.merge(v1, v2) end)
  end

  defp build_hourly_map(value_list, key) when is_list(value_list) do
    value_list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {value, index}, acc -> Map.put(acc, index + 1, %{key => value}) end)
  end

  defp host, do: Application.get_env(:forecaster, :weather_host_impl, ProdHost)
end
