defmodule Forecaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Forecaster.Scraper,
      Forecaster.Publisher,
      Forecaster.Scheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Forecaster.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
