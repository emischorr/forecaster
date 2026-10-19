defmodule PvForecast do
  alias PvForecast.Ensemble
  alias PvForecast.Model
  alias PvForecast.TrainingData

  def create_model(opts \\ []) do
    {inputs, targets} =
      training_data(opts)
      |> Model.prepare_data()

    # Train model with validation
    IO.puts("Training model with validation...")

    trained_model =
      Model.train_model(inputs, targets,
        epochs: 200,
        validation_split: 0.2,
        early_stopping_patience: 15
      )

    # Evaluate model performance
    case Model.evaluate_model(trained_model) do
      {:ok, metrics} ->
        IO.puts("Model Performance:")
        IO.puts("  RMSE: #{Float.round(metrics.rmse, 2)} kWh")
        IO.puts("  MAE: #{Float.round(metrics.mae, 2)} kWh")
        IO.puts("  R²: #{Float.round(metrics.r_squared, 3)}")

      {:error, reason} ->
        IO.puts("Could not evaluate model: #{reason}")
    end

    # Save the trained model with version info
    case Model.save_model(trained_model, "pv_forecast_model.bin",
           version: "1.0.0",
           description: "Initial PV forecast model with 4 features"
         ) do
      {:ok, message} -> IO.puts(message)
      {:error, reason} -> IO.puts("Save failed: #{reason}")
    end

    # Demonstrate loading the model with validation
    case Model.load_model("pv_forecast_model.bin", strict_validation: true) do
      {:ok, loaded_model} ->
        IO.puts("Model loaded successfully!")
        IO.puts("Model version: #{loaded_model.model_version}")
        IO.puts("Model created at: #{loaded_model.metadata.created_at}")
        IO.puts("Training samples: #{loaded_model.metadata.training_samples}")

        # Test normal prediction
        prediction = Model.predict_single(loaded_model, 15.0, 8.5, 0.0, ~D[2026-05-30])

        IO.puts(
          "Prediction for May 30th (15°C, 8.5h, 0mm): #{Float.round(prediction |> Nx.squeeze() |> Nx.to_number(), 1)} kWh"
        )

      {:error, reason} ->
        IO.puts("Load failed: #{reason}")
    end

    # Demonstrate model migration
    # IO.puts("\n=== Model Migration Example ===")
    # IO.puts("Simulating migration from v1.0.0 to v1.1.0 (adding humidity)...")

    # case load_model("pv_forecast_model.bin") do
    #   {:ok, old_model} ->
    #     case migrate_model(old_model, "1.1.0") do
    #       {:ok, migrated_model} ->
    #         IO.puts("✓ Migration successful!")
    #         IO.puts("Old features: #{inspect(old_model.metadata.features)}")
    #         IO.puts("New features: #{inspect(@feature_definitions["1.1.0"].features)}")
    #         IO.puts("⚠ Retraining required with humidity data")

    #       {:error, reason} ->
    #         IO.puts("Migration failed: #{reason}")
    #     end

    #   {:error, reason} ->
    #     IO.puts("Could not load model for migration: #{reason}")
    # end

    trained_model
  end

  @doc """
  Trains the ensemble on `TrainingData.daily_data/1` and saves it.

  Options:
    - path: Output file (default: the configured `:model_path`)
    - data: Training data CSV (default: the configured `:training_data_path`)
    - epochs: Max training epochs (default: 200)
  """
  def create_ensemble(opts \\ []) do
    path = Keyword.get(opts, :path, Application.get_env(:pv_forecast, :model_path))
    epochs = Keyword.get(opts, :epochs, 200)

    {inputs, targets} =
      training_data(opts)
      |> Model.prepare_data()

    # Train model with validation
    IO.puts("Training model with validation...")

    trained_ensemble =
      Ensemble.train_ensemble(inputs, targets,
        epochs: epochs,
        validation_split: 0.2,
        early_stopping_patience: 15
      )

    # Evaluate model performance
    metrics =
      case Ensemble.evaluate_ensemble(trained_ensemble) do
        {:ok, %{ensemble: ensemble} = metrics} ->
          IO.puts("Ensemble Performance:")
          IO.puts("  RMSE: #{Float.round(ensemble.rmse, 2)} kWh")
          IO.puts("  MAE: #{Float.round(ensemble.mae, 2)} kWh")
          IO.puts("  R²: #{Float.round(ensemble.r_squared, 3)}")
          metrics

        {:error, reason} ->
          IO.puts("Could not evaluate model: #{reason}")
          nil
      end

    # Save the trained model with version info
    case Ensemble.save_ensemble(trained_ensemble, path,
           description: "PV forecast ensemble with 4 features",
           metrics: metrics
         ) do
      {:ok, message} -> IO.puts(message)
      {:error, reason} -> IO.puts("Save failed: #{reason}")
    end

    # Demonstrate loading the model with validation
    case Ensemble.load_ensemble(path, strict_validation: true) do
      {:ok, loaded_ensemble} ->
        IO.puts("Ensemble loaded successfully!")
        IO.puts("Model version: #{loaded_ensemble.metadata.version}")
        IO.puts("Model created at: #{loaded_ensemble.metadata.created_at}")
        IO.puts("Training samples: #{loaded_ensemble.metadata.training_samples}")

        # Test normal prediction
        prediction =
          Ensemble.predict_single_ensemble(loaded_ensemble, 15.0, 8.5, 0.0, ~D[2026-05-30])

        IO.puts(
          "Prediction for May 30th (15°C, 8.5h, 0mm): #{Float.round(prediction |> Nx.squeeze() |> Nx.to_number(), 1)} kWh"
        )

      {:error, reason} ->
        IO.puts("Load failed: #{reason}")
    end
  end

  defp training_data(opts) do
    case Keyword.get(opts, :data) do
      nil -> TrainingData.daily_data()
      path -> TrainingData.daily_data(path)
    end
  end
end
