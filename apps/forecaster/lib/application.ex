defmodule Forecaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [Forecaster.Events] ++ scraper_children() ++ publisher_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Forecaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp scraper_children do
    if Application.get_env(:forecaster, :scraper_enabled, true),
      do: [Forecaster.Scraper],
      else: []
  end

  # The scheduler only triggers the publisher, so both run together
  defp publisher_children do
    if Application.get_env(:forecaster, :publish_enabled, true),
      do: [Forecaster.Publisher, Forecaster.Scheduler],
      else: []
  end
end
