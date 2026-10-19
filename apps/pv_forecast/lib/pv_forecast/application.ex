defmodule PvForecast.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {PvForecast.ModelServer, path: Application.fetch_env!(:pv_forecast, :model_path)}
      ] ++ publisher_children() ++ http_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PvForecast.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp publisher_children do
    if Application.get_env(:pv_forecast, :publish_enabled, true),
      do: [PvForecast.Publisher],
      else: []
  end

  defp http_children do
    if Application.get_env(:pv_forecast, :http_enabled, true) do
      port = Application.fetch_env!(:pv_forecast, :port)
      [{Bandit, plug: PvForecast.Web.Router, port: port}]
    else
      []
    end
  end
end
