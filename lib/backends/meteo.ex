defmodule Forecaster.Backends.Meteo do
  alias Forecaster.Backends.MeteoParser

  defmodule Host do
    @callback base_url() :: String.t()
  end

  defmodule ProdHost do
    @behaviour Host
    def base_url, do: "https://www.meteoblue.com/weather/week/"
  end

  @spec forecast_range :: Range.t()
  def forecast_range, do: 1..7

  @spec forecast(String.t()) :: list({integer(), map()})
  def forecast(place) do
    forecast_range()
    |> Enum.map(&forecast_day(place, &1))
  end

  @spec forecast_day(String.t(), integer()) :: {integer(), map()}
  defp forecast_day(place, day) do
    forecast =
      place
      |> url_for(day)
      |> fetch_html()
      |> MeteoParser.extract_forecast()

    {day, forecast}
  end

  defp url_for(loc_id, day), do: "#{host().base_url()}#{loc_id}?day=#{day}"

  defp fetch_html(url) do
    Req.new(url: url, compress_body: true)
    |> Req.Request.put_header(
      "User-Agent",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:136.0) Gecko/20100101 Firefox/136.0"
    )
    |> Req.Request.put_header(
      "Accept",
      "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    )
    |> Req.Request.put_header("Accept-Language", "en-US;q=0.7,en;q=0.3")
    |> Req.Request.put_header("Connection", "keep-alive")
    |> Req.Request.put_header(
      "Cookie",
      "locale=en_US; darkmode=true; speed=METER_PER_SECOND; extendview=true; mb=26uv0n6hj6lehh6bqva2ajo07p"
    )
    |> Req.Request.put_header("Upgrade-Insecure-Requests", "1")
    |> Req.Request.put_header("Sec-Fetch-Dest", "document")
    |> Req.Request.put_header("Sec-Fetch-Mode", "navigate")
    |> Req.Request.put_header("Sec-Fetch-Site", "same-origin")
    |> Req.Request.put_header("Sec-Fetch-User", "?1")
    |> Req.Request.put_header("Priority", "u=0, i")
    |> Req.get()
    |> handle_response()

    # |> write_to_file("weather.html")
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}
  defp handle_response({:ok, %Req.Response{status: status}}), do: {:error, status}
  defp handle_response({:error, error}), do: {:error, error}

  # defp write_to_file({:ok, body}, file_path) do
  #   File.write(file_path, body)
  #   {:ok, body}
  # end

  defp host, do: Application.get_env(:forecaster, :weather_host_impl, ProdHost)
end
