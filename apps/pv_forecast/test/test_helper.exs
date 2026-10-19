defmodule PvForecast.TestFixtures do
  @moduledoc false

  @path "tmp/test/ensemble.bin"
  # Synthetic data, the real training data is not part of the repo
  @training_data "test/fixtures/training_sample.csv"

  # Trains a small ensemble once per test run and saves it to disk
  def ensemble_path do
    unless File.exists?(@path) and :persistent_term.get({__MODULE__, :trained}, false) do
      File.mkdir_p!(Path.dirname(@path))

      {inputs, targets} =
        @training_data
        |> PvForecast.TrainingData.daily_data()
        |> PvForecast.Model.prepare_data()

      ExUnit.CaptureIO.capture_io(fn ->
        ensemble = PvForecast.Ensemble.train_ensemble(inputs, targets, epochs: 3)
        {:ok, _} = PvForecast.Ensemble.save_ensemble(ensemble, @path)
      end)

      :persistent_term.put({__MODULE__, :trained}, true)
    end

    @path
  end
end

ExUnit.start()
