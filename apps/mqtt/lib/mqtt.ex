defmodule MQTT do
  @moduledoc """
  Publishes values to the MQTT broker, shared by the other umbrella apps.

  All topics live under the configured namespace (`config :mqtt, namespace: ...`)
  and are published retained. The connection itself is managed by this app.
  """

  @doc """
  Publishes `value` under `<namespace>/<subtopic>`, e.g. `MQTT.publish("1/temp_max", 14)`.

  The subtopic is lowercased and spaces are replaced by underscores.
  """
  def publish(subtopic, value) do
    MQTT.Connection.publish(to_string(subtopic), to_string(value))
  end
end
