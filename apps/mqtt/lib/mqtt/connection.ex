defmodule MQTT.Connection do
  @moduledoc false
  # Holds the connection to the broker. Announces `<namespace>/status` as "online"
  # on startup, with "offline" as last will.

  use GenServer
  require Logger

  # Client

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def publish(subtopic, value) do
    GenServer.cast(__MODULE__, {:publish, subtopic, value})
  end

  # Server (callbacks)

  @impl true
  def init(_opts) do
    Logger.info("Starting MQTT connection")
    {:ok, %{}, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    {:ok, client_id} = connect(client_id())
    publish(client_id, "#{namespace()}/status", "online")
    {:noreply, Map.put(state, :client_id, client_id)}
  end

  @impl true
  def handle_cast({:publish, subtopic, value}, state) do
    publish(state.client_id, topic(subtopic), value)
    {:noreply, state}
  end

  defp connect(client_id) do
    config = Application.get_all_env(:mqtt)

    case Tortoise.Supervisor.start_child(
           client_id: client_id,
           handler: {Tortoise.Handler.Logger, []},
           server: {Tortoise.Transport.Tcp, host: config[:host], port: config[:port]},
           user_name: config[:username],
           password: config[:password],
           will: %Tortoise.Package.Publish{
             topic: "#{namespace()}/status",
             payload: "offline",
             qos: 1,
             retain: true
           }
         ) do
      {:ok, _pid} -> {:ok, client_id}
      {:error, reason} -> {:error, reason}
    end
  end

  # Bounded, so a broker that never connects can't block this process forever
  defp publish(client_id, topic, value) do
    with {:error, reason} <-
           Tortoise.publish(client_id, topic, value, qos: 0, retain: true, timeout: 5_000) do
      Logger.warning("MQTT publish to #{topic} failed: #{inspect(reason)}")
    end
  end

  # Unique per instance, so e.g. a dev and a Docker instance don't take over each other's session
  defp client_id do
    {:ok, host} = :inet.gethostname()
    suffix = :rand.uniform(0xFFFFFF) |> Integer.to_string(16) |> String.downcase()
    "forecaster_#{host}_#{suffix}"
  end

  defp topic(subtopic) do
    "#{namespace()}/#{subtopic}" |> String.downcase() |> String.replace(" ", "_")
  end

  defp namespace, do: Application.get_env(:mqtt, :namespace)
end
