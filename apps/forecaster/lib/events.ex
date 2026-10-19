defmodule Forecaster.Events do
  @moduledoc """
  Minimal pub/sub so other processes (or umbrella apps) can react to forecaster events
  without the forecaster knowing about them.

  Subscribers receive `{Forecaster.Events, event}` messages, e.g. `{Forecaster.Events, :forecast_updated}`.
  """

  @registry __MODULE__

  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc "Subscribes the calling process to `event`."
  def subscribe(event) do
    {:ok, _} = Registry.register(@registry, event, nil)
    :ok
  end

  @doc "Sends `event` to all subscribed processes."
  def broadcast(event) do
    Registry.dispatch(@registry, event, fn subscribers ->
      for {pid, _} <- subscribers, do: send(pid, {__MODULE__, event})
    end)
  end
end
