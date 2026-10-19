defmodule Forecaster.MQTT do
  def client(), do: "forecaster#{Enum.random(1..9)}"

  def connect(), do: connect(client())

  def connect(client_id) do
    config = Application.get_env(:forecaster, :mqtt)

    case Tortoise.Supervisor.start_child(
           client_id: client_id,
           handler: {Tortoise.Handler.Logger, []},
           server: {Tortoise.Transport.Tcp, host: config[:host], port: config[:port]},
           user_name: config[:username],
           password: config[:password],
           will: %Tortoise.Package.Publish{
             topic: "#{config[:namespace]}/status",
             payload: "offline",
             qos: 1,
             retain: true
           }
         ) do
      {:ok, _pid} -> {:ok, client_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def publish_meta(client_id) do
    ns = Application.get_env(:forecaster, :mqtt)[:namespace]
    Tortoise.publish(client_id, "#{ns}/status", "online", qos: 0, retain: true)
  end

  def publish_daily_forecast(client_id, day, key, value) do
    ns = Application.get_env(:forecaster, :mqtt)[:namespace]
    topic = sanitize_topic("#{ns}/#{day}/#{key}")
    Tortoise.publish(client_id, topic, value, qos: 0, retain: true)
  end

  def publish_current_hour(client_id, key, value) do
    ns = Application.get_env(:forecaster, :mqtt)[:namespace]
    topic = sanitize_topic("#{ns}/current_hour/#{key}")
    Tortoise.publish(client_id, topic, value, qos: 0, retain: true)
  end

  defp sanitize_topic(topic) do
    topic |> String.downcase() |> String.replace(" ", "_")
  end
end
