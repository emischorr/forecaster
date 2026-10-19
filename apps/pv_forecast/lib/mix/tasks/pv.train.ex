defmodule Mix.Tasks.Pv.Train do
  @shortdoc "Trains the PV forecast ensemble and saves it to disk"
  @moduledoc """
  Trains the ensemble on a training data CSV and writes the model file.

      mix pv.train [--data PATH] [--output PATH] [--epochs N]

  `--data` defaults to the configured `:training_data_path` (env `PV_TRAINING_DATA`),
  `--output` to the configured `:model_path` (env `MODEL_PATH`). A running
  server picks the new file up after `PvForecast.ModelServer.reload()` or a restart.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl true
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args, strict: [data: :string, output: :string, epochs: :integer])

    # Start only EXLA, not the HTTP server
    {:ok, _} = Application.ensure_all_started(:exla)

    PvForecast.create_ensemble(
      path: Keyword.get(opts, :output, Application.fetch_env!(:pv_forecast, :model_path)),
      epochs: Keyword.get(opts, :epochs, 200),
      data: Keyword.get(opts, :data)
    )
  end
end
