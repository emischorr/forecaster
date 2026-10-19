defmodule Forecaster.Events do
  @moduledoc """
  Minimal pub/sub so other processes (or umbrella apps) can react to forecaster events
  without the forecaster knowing about them.

  Subscribers receive `{Forecaster, event, payload}` messages, e.g. `{Forecaster, :forecast_updated, forecasts}`.
  Other apps subscribe through `Forecaster.subscribe/0`.
  """

  @registry __MODULE__

  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc "Subscribes the calling process to `event`."
  def subscribe(event) do
    {:ok, _} = Registry.register(@registry, event, nil)
    :ok
  end

  def subscribe_forecast_updated, do: subscribe(:forecast_updated)

  @doc "Sends `event` with `payload` to all subscribed processes."
  def broadcast(event, payload) do
    Registry.dispatch(@registry, event, fn subscribers ->
      for {pid, _} <- subscribers, do: send(pid, {Forecaster, event, payload})
    end)
  end
end
