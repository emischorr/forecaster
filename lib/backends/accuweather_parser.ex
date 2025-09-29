defmodule Forecaster.Backends.AccuweatherParser do
  require Logger

  @spec extract_forecast({:ok, binary()} | {:error, term()}) :: map()
  def extract_forecast({:ok, html}) do
    {:ok, parsed_html} = Floki.parse_document(html)

    %{
      hour: hourly_data(parsed_html)
    }
  end

  def extract_forecast({:error, error}) do
    Logger.warning("Could not load weather data: #{inspect(error)}")
    %{}
  end

  defp hourly_data(parsed_html) do
    hour_data = Floki.find(parsed_html, ".hourly-wrapper .hour .hourly-content-container p")

    cloud_cover =
      hour_data
      |> filter_metric("cloud cover")
      |> Enum.map(&content/1)
      |> Enum.map(&String.replace(&1, "%", ""))
      |> build_hourly_map(:cloud_cover)

    brightness =
      hour_data
      |> filter_metric("acculumen brightness index")
      |> Enum.map(&content/1)
      |> Enum.map(&String.replace(&1, ~r/\D/, ""))
      |> build_hourly_map(:brightness)

    cloud_cover
    |> Map.merge(brightness, fn _key, v1, v2 -> Map.merge(v1, v2) end)
  end

  defp filter_metric(elements, metric_name) do
    Enum.filter(elements, fn {"p", [], [metric, {"span", _attr, _content}]} ->
      metric |> String.downcase() |> String.starts_with?(metric_name)
    end)
  end

  defp content({_tag, _attr, [content]}), do: String.trim(content)

  defp content({_tag, _attr, list}) do
    list
    |> Enum.filter(&is_tuple/1)
    |> List.last({"", [], []})
    |> elem(2)
    |> List.last()
    |> String.trim()
  end

  defp build_hourly_map(value_list, key) when is_list(value_list) do
    offset =
      if length(value_list) != 24 do
        timezone() |> DateTime.now!() |> Map.get(:hour) |> Kernel.+(1)
      else
        0
      end

    value_list
    |> Enum.with_index(offset)
    |> Enum.reduce(%{}, fn {value, index}, acc -> Map.put(acc, index, %{key => value}) end)
  end

  defp timezone() do
    Application.get_env(:forecaster, :timezone, "Europe/Berlin")
  end
end
