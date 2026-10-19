defmodule MQTT.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children =
      if Application.get_env(:mqtt, :enabled, true),
        do: [MQTT.Connection],
        else: []

    opts = [strategy: :one_for_one, name: MQTT.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
