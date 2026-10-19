defmodule PvForecast.ModelServer do
  @moduledoc """
  Holds the trained ensemble in memory and serves predictions.

  The ensemble is loaded from disk at startup and each member is compiled
  once with the configured `:defn_compiler` (`Nx.Defn.Evaluator` in prod,
  EXLA in dev/test). If the file is missing or unusable the server keeps
  running in a "not ready" state and predictions return `{:error, :not_ready}`.

  After retraining, swap in the new file from a remote shell with `reload/0`
  (or restart the service).
  """

  use GenServer
  require Logger

  alias PvForecast.Ensemble

  @call_timeout 30_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Predicts daily PV production for a `{batch, 4}` feature tensor.

  Returns `{:ok, %{mean: [float], min: [float], max: [float]}}` with one value
  per row, where min/max are the lowest and highest member predictions.
  """
  def predict(inputs, server \\ __MODULE__) do
    GenServer.call(server, {:predict, inputs}, @call_timeout)
  end

  @doc "Reloads the model file. Keeps the current model if the new one is unusable."
  def reload(server \\ __MODULE__) do
    GenServer.call(server, :reload, @call_timeout)
  end

  @doc "Returns status and metadata of the loaded model."
  def info(server \\ __MODULE__) do
    GenServer.call(server, :info)
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    {:ok, load(path)}
  end

  @impl true
  def handle_call({:predict, _inputs}, _from, %{status: :not_ready} = state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:predict, inputs}, _from, state) do
    {:reply, {:ok, run_members(state.members, inputs)}, state}
  end

  def handle_call(:reload, _from, state) do
    new_state = load(state.path)

    case new_state do
      %{status: :ready} ->
        {:reply, :ok, new_state}

      %{reason: reason} ->
        # Keep serving the previous model if the new one is unusable
        {:reply, {:error, reason}, if(state.status == :ready, do: state, else: new_state)}
    end
  end

  def handle_call(:info, _from, state) do
    {:reply, Map.drop(state, [:members]), state}
  end

  defp load(path) do
    with {:ok, ensemble} <- Ensemble.load_ensemble(path),
         {:ok, members} <- compile_members(ensemble) do
      Logger.info("Loaded PV forecast ensemble from #{path}")

      %{
        status: :ready,
        path: path,
        members: members,
        metadata: ensemble.metadata,
        loaded_at: DateTime.utc_now()
      }
    else
      {:error, reason} ->
        Logger.warning("PV forecast model not ready (#{path}): #{reason}")
        %{status: :not_ready, path: path, reason: reason, metadata: nil, loaded_at: nil}
    end
  end

  defp compile_members(ensemble) do
    members =
      Enum.map(ensemble.models, fn %{model: model, params: params} ->
        {_init_fn, predict_fn} = Axon.build(model, compiler: defn_compiler())
        %{predict_fn: predict_fn, params: Nx.backend_transfer(params, inference_backend())}
      end)

    # Smoke test: files saved before params were copied off the device
    # deserialize fine but hold dangling buffer references
    run_members(members, Nx.broadcast(Nx.tensor(0.0, type: :f32), {1, 4}))
    {:ok, members}
  rescue
    error ->
      {:error, "model file has no usable weights (retrain it): #{Exception.message(error)}"}
  end

  defp defn_compiler, do: Application.get_env(:pv_forecast, :defn_compiler, Nx.Defn.Evaluator)

  defp inference_backend,
    do: Application.get_env(:pv_forecast, :inference_backend, Nx.BinaryBackend)

  defp run_members(members, inputs) do
    predictions =
      members
      |> Enum.map(fn %{predict_fn: predict_fn, params: params} ->
        predict_fn.(params, %{"features" => inputs}) |> Nx.reshape({:auto})
      end)
      |> Nx.stack()
      # Negative energy is not physical
      |> Nx.max(0.0)

    %{
      mean: predictions |> Nx.mean(axes: [0]) |> Nx.to_flat_list(),
      min: predictions |> Nx.reduce_min(axes: [0]) |> Nx.to_flat_list(),
      max: predictions |> Nx.reduce_max(axes: [0]) |> Nx.to_flat_list()
    }
  end
end
