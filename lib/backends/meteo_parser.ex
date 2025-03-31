defmodule Forecaster.Backends.MeteoParser do
  require Logger

  @spec extract_forecast({:ok, binary()} | {:error, term()}) :: map()
  def extract_forecast({:ok, html}) do
    {:ok, parsed_html} = Floki.parse_document(html)

    %{
      temp_max: daily_max_temp(parsed_html),
      temp_min: daily_min_temp(parsed_html),
      precip_max: daily_max_precipitation(parsed_html),
      sun: daily_sunshine(parsed_html),
      uv: daily_uv(parsed_html),
      hour: hourly_data(parsed_html)
    }
  end

  def extract_forecast({:error, error}) do
    Logger.warning("Could not load weather data: #{inspect(error)}")
    %{}
  end

  defp daily_max_temp(parsed_html) do
    Floki.find(parsed_html, "div.tab.active div.temps > div.tab-temp-max")
    |> check("div.tab-temp-max")
    |> content()
    |> String.replace("\u00A0°C", "")
  end

  defp daily_min_temp(parsed_html) do
    Floki.find(parsed_html, "div.tab.active div.temps > div.tab-temp-min")
    |> check("div.tab-temp-min")
    |> content()
    |> String.replace("\u00A0°C", "")
  end

  defp daily_max_precipitation(parsed_html) do
    Floki.find(parsed_html, "div.tab.active div.data > div.tab-precip")
    |> check("div.tab-precip")
    |> content()
    |> String.replace(" mm", "")
    |> max_rain()
  end

  defp daily_sunshine(parsed_html) do
    Floki.find(parsed_html, "div.tab.active div.data > div.tab-sun")
    |> check("div.tab-sun")
    |> content()
    |> String.replace(" h", "")
  end

  defp daily_uv(parsed_html) do
    Floki.find(parsed_html, "div.tab-detail.active div.sun div.uv-index")
    |> check("div.uv-index")
    |> content()
    |> String.replace("UV ", "")
  end

  defp hourly_data(parsed_html) do
    temps =
      parsed_html
      |> Floki.find("div.tab-detail.active #hourly_forecast tr.temps td span")
      |> Enum.map(&content/1)
      |> Enum.map(&String.replace(&1, "°", ""))
      |> build_hourly_map(:temperature)

    conditions =
      parsed_html
      |> Floki.find("div.tab-detail.active #hourly_forecast img.picon")
      |> Enum.map(fn {_tag, attr, _content} ->
        Enum.find_value(attr, fn {key, value} -> if key == "title", do: value end)
      end)
      |> build_hourly_map(:condition)

    Map.merge(temps, conditions, fn _key, v1, v2 -> Map.merge(v1, v2) end)
  end

  defp check(nil, element) do
    Logger.warning("Element '#{inspect(element)}' not found!")
    ""
  end

  defp check(content, _element), do: content

  defp content(list) when is_list(list), do: content(List.first(list))

  defp content({_tag, _attr, [content]}), do: String.trim(content)

  defp content({_tag, _attr, list}),
    do: list |> Enum.reject(&is_tuple/1) |> List.last("") |> String.trim()

  defp max_rain("-"), do: "0"
  defp max_rain(min_max) when is_binary(min_max), do: String.split(min_max, ~r|.-|) |> List.last()

  defp build_hourly_map(value_list, key) when is_list(value_list) do
    value_list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {value, index}, acc -> Map.put(acc, index, %{key => value}) end)
  end
end
