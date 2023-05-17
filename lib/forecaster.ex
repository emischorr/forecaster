defmodule Forecaster do
  use GenServer
  require Logger

  alias Forecaster.{Weather, MQTT}

  @moduledoc """
  Documentation for `Forecaster`.
  """

  # Client

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end


  # Server (callbacks)

  @impl true
  def init(_opts) do
    Logger.info "Starting Forecaster"
    {:ok, %{}, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    {:ok, mqtt_client} = MQTT.connect()
    MQTT.publish_meta(mqtt_client)
    Process.send_after(self(), :update, 1000)
    {:noreply, Map.put(state, :mqtt_client, mqtt_client)}
  end

  @impl true
  def handle_info(:update, state) do
    Logger.info "Updating forecast"

    Enum.each(Weather.forecast(place()), fn {day, forecast} ->
      publish_forecast(forecast, day, state.mqtt_client)
    end)

    Process.send_after(self(), :update, update_interval())
    {:noreply, state}
  end


  defp publish_forecast(forecast, day, mqtt_client) do
    Enum.each(forecast, fn {key, value} ->
      MQTT.publish(mqtt_client, day, Atom.to_string(key), value)
    end)
  end

  defp update_interval() do
    Application.get_env(:forecaster, :update_interval, :timer.hours(2))
  end

  defp place() do
    Application.get_env(:forecaster, :place)
  end
end
