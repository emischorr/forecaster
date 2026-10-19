defmodule PvForecast.Model do
  @moduledoc """
  PV Production Forecast Neural Network
  Features: max_temperature, sunshine_hours, rain_mm, solar_declination_angle
  Target: daily_pv_production
  """

  alias PvForecast.Utils

  @current_model_version "1.0.0"
  @compatible_versions ["1.0.0"]
  @model_config %{type: "pv_forecast", features: 4}

  # Data preprocessing
  def prepare_data(raw_data) do
    # Assuming raw_data is a list of maps with keys:
    # %{date: ~D[2024-01-15], max_temp: 12.5, sunshine_hours: 6.2, rain_mm: 0.2, pv_production: 15.8}

    processed =
      Enum.map(raw_data, fn record ->
        inputs = features(record)

        # Target (PV production)
        target = [record.pv_production]

        {inputs, target}
      end)

    # Separate inputs and targets
    {inputs, targets} = Enum.unzip(processed)

    # Convert to tensors
    input_tensor = inputs |> Nx.tensor(type: :f32)
    target_tensor = targets |> Nx.tensor(type: :f32)

    {input_tensor, target_tensor}
  end

  # Input features [temp, sunshine, rain, declination] for one day
  def features(%{
        date: date,
        max_temp: max_temp,
        sunshine_hours: sunshine_hours,
        rain_mm: rain_mm
      }) do
    [max_temp, sunshine_hours, rain_mm, Utils.solar_declination(date)]
  end

  # Split data into train/validation sets
  def train_val_split(input_data, target_data, split_ratio \\ 0.8) do
    num_samples = Nx.axis_size(input_data, 0)
    train_size = round(num_samples * split_ratio)

    # Shuffle indices
    indices = Enum.shuffle(0..(num_samples - 1))
    train_indices = Enum.take(indices, train_size)
    val_indices = Enum.drop(indices, train_size)

    # Split the data
    train_inputs = Nx.take(input_data, Nx.tensor(train_indices))
    train_targets = Nx.take(target_data, Nx.tensor(train_indices))
    val_inputs = Nx.take(input_data, Nx.tensor(val_indices))
    val_targets = Nx.take(target_data, Nx.tensor(val_indices))

    {train_inputs, train_targets, val_inputs, val_targets}
  end

  # Build the neural network model with layer normalization
  def build_model() do
    # 4 input features
    Axon.input("features", shape: {nil, 4})
    # Built-in layer normalization
    |> Axon.layer_norm()
    # First hidden layer
    |> Axon.dense(32, activation: :relu)
    # Regularization
    |> Axon.dropout(rate: 0.2)
    # Second hidden layer
    |> Axon.dense(16, activation: :relu)
    # Regularization
    |> Axon.dropout(rate: 0.2)
    # Third hidden layer
    |> Axon.dense(8, activation: :relu)
    # Output layer (regression)
    |> Axon.dense(1, activation: :linear)
  end

  # Training function
  def train_model(input_data, target_data, opts \\ []) do
    epochs = Keyword.get(opts, :epochs, 100)
    validation_split = Keyword.get(opts, :validation_split, 0.2)
    early_stopping_patience = Keyword.get(opts, :early_stopping_patience, 10)

    # Split into train/validation
    {train_inputs, train_targets, val_inputs, val_targets} =
      train_val_split(input_data, target_data, 1.0 - validation_split)

    # Prepare validation data as list of {input, target} tuples
    val_data = [{val_inputs, val_targets}]
    train_data = [{train_inputs, train_targets}]

    # Build model
    model = build_model()

    optimizer = Polaris.Optimizers.adam(learning_rate: 0.01)

    # Training loop with validation
    trained_state =
      model
      |> Axon.Loop.trainer(:mean_squared_error, optimizer)
      |> Axon.Loop.metric(:mean_absolute_error, "MAE")
      |> Axon.Loop.validate(model, val_data)
      |> Axon.Loop.early_stop("validation_loss", mode: :min, patience: early_stopping_patience)
      |> Axon.Loop.run(train_data, Axon.ModelState.empty(),
        epochs: epochs,
        compiler: EXLA
      )

    # Return trained model
    %{
      model: model,
      params: trained_state,
      validation_data: %{
        inputs: val_inputs,
        targets: val_targets
      }
    }
  end

  # Prediction function
  def predict(trained_model, new_data) do
    %{model: model, params: params} = trained_model

    # Validate input data shape
    input_shape = Nx.shape(new_data)
    expected_features = 4

    new_data =
      case input_shape do
        {_batch_size, ^expected_features} ->
          new_data

        {^expected_features} ->
          # Single prediction, reshape to batch
          Nx.reshape(new_data, {1, expected_features})

        _ ->
          raise ArgumentError,
                "Input data must have shape {batch_size, #{expected_features}} or {#{expected_features}}, got #{inspect(input_shape)}"
      end

    # Make prediction - normalization happens automatically
    Axon.predict(model, params, %{"features" => new_data})
  end

  # Helper for single prediction
  def predict_single(trained_model, max_temp, sunshine_hours, rain_mm, date) do
    input_tensor =
      Nx.tensor(
        [
          features(%{
            date: date,
            max_temp: max_temp,
            sunshine_hours: sunshine_hours,
            rain_mm: rain_mm
          })
        ],
        type: :f32
      )

    prediction = predict(trained_model, input_tensor)
    # Squeeze to remove batch dimension for single predictions
    Nx.squeeze(prediction)
  end

  # Save trained model to disk
  def save_model(trained_model, filepath, opts \\ []) do
    model_version = Keyword.get(opts, :version, @current_model_version)
    description = Keyword.get(opts, :description, "PV forecast model")

    serializable_model = %{
      # Version and compatibility info
      model_version: model_version,
      compatible_versions: @compatible_versions,
      model_config: @model_config,
      # Copy params off the EXLA device, otherwise only buffer references get serialized
      params: Nx.backend_copy(trained_model.params, Nx.BinaryBackend),
      metadata: %{
        description: description,
        features: ["max_temp", "sunshine_hours", "rain_mm", "solar_declination"],
        training_samples: get_training_sample_count(trained_model),
        created_at: DateTime.utc_now()
      }
    }

    binary_data = :erlang.term_to_binary(serializable_model, [:compressed])

    case File.write(filepath, binary_data) do
      :ok -> {:ok, "Model saved to #{filepath}"}
      {:error, reason} -> {:error, "Failed to save model: #{reason}"}
    end
  end

  # Load trained model from disk
  #
  # Options:
  #   - strict_validation: When true (default), a model saved with an incompatible
  #     version or feature configuration is rejected. When false, it is loaded
  #     anyway and a warning is logged (e.g. to migrate an old model).
  def load_model(filepath, opts \\ []) do
    strict_validation = Keyword.get(opts, :strict_validation, true)

    case File.read(filepath) do
      {:ok, binary_data} ->
        try do
          serializable_model = :erlang.binary_to_term(binary_data)

          with :ok <- validate_model(serializable_model, strict_validation) do
            trained_model = %{
              # Reconstruct the model
              model: build_model(),
              params: serializable_model.params,
              metadata: serializable_model.metadata,
              model_version: serializable_model.model_version
            }

            {:ok, trained_model}
          end
        rescue
          error -> {:error, "Failed to deserialize model: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read model file: #{reason}"}
    end
  end

  # Missing keys are always an error, version/config mismatches only when strict
  defp validate_model(serializable_model, strict_validation) do
    required_keys = [:params, :metadata, :model_version]

    case Enum.reject(required_keys, &is_map_key(serializable_model, &1)) do
      [] ->
        problems =
          [
            if serializable_model.model_version not in @compatible_versions do
              "version #{inspect(serializable_model.model_version)} is not one of #{inspect(@compatible_versions)}"
            end,
            if Map.get(serializable_model, :model_config) != @model_config do
              "model config #{inspect(Map.get(serializable_model, :model_config))} does not match #{inspect(@model_config)}"
            end
          ]
          |> Enum.reject(&is_nil/1)

        Utils.check_compatibility("model", problems, strict_validation)

      missing ->
        {:error, "Invalid model file, missing #{inspect(missing)}"}
    end
  end

  # Evaluate model performance
  def evaluate_model(trained_model) do
    case Map.get(trained_model, :validation_data) do
      nil ->
        {:error, "No validation data available"}

      %{inputs: val_inputs, targets: val_targets} ->
        predictions = predict(trained_model, val_inputs)

        # Calculate metrics
        mse = Nx.mean(Nx.pow(Nx.subtract(predictions, val_targets), 2))
        mae = Nx.mean(Nx.abs(Nx.subtract(predictions, val_targets)))

        # R² score
        ss_res = Nx.sum(Nx.pow(Nx.subtract(val_targets, predictions), 2))
        ss_tot = Nx.sum(Nx.pow(Nx.subtract(val_targets, Nx.mean(val_targets)), 2))
        r_squared = Nx.subtract(1.0, Nx.divide(ss_res, ss_tot))

        metrics = %{
          mse: Nx.to_number(mse),
          mae: Nx.to_number(mae),
          rmse: :math.sqrt(Nx.to_number(mse)),
          r_squared: Nx.to_number(r_squared)
        }

        {:ok, metrics}
    end
  end

  # Helper to get training sample count from model
  defp get_training_sample_count(trained_model) do
    case Map.get(trained_model, :validation_data) do
      %{inputs: val_inputs} ->
        # Estimate total samples (assuming 80/20 split)
        val_size = Nx.axis_size(val_inputs, 0)
        round(val_size / 0.2)

      _ ->
        "unknown"
    end
  end

  # # Example usage
  # def run_example() do
  #   # Generate sample training data
  #   sample_data = generate_sample_data(100)

  #   # Prepare training data
  #   {inputs, targets} = prepare_data(sample_data)

  #   # Train model
  #   IO.puts("Training PV forecast model...")
  #   trained_model = train_model(inputs, targets, epochs: 50)

  #   # Evaluate model
  #   case evaluate_model(trained_model) do
  #     {:ok, metrics} ->
  #       IO.puts("Model Performance:")
  #       IO.puts("  RMSE: #{Float.round(metrics.rmse, 2)} kWh")
  #       IO.puts("  MAE: #{Float.round(metrics.mae, 2)} kWh")
  #       IO.puts("  R²: #{Float.round(metrics.r_squared, 3)}")

  #     {:error, reason} ->
  #       IO.puts("Could not evaluate model: #{reason}")
  #   end

  #   # Save model
  #   case save_model(trained_model, "pv_model.bin") do
  #     {:ok, message} -> IO.puts(message)
  #     {:error, reason} -> IO.puts("Save failed: #{reason}")
  #   end

  #   # Test prediction
  #   # May 30th
  #   prediction = predict_single(trained_model, 20.0, 8.0, ~D[2015-05-30])

  #   IO.puts(
  #     "Prediction for 20°C, 8h sunshine on May 30th: #{Float.round(Nx.to_number(prediction), 1)} kWh"
  #   )

  #   trained_model
  # end
end
