defmodule PvForecast.Ensemble do
  @moduledoc """
  PV Production Forecast Ensemble Model

  This module implements ensemble learning for PV forecasting by training
  multiple neural networks with different configurations and combining
  their predictions to improve accuracy and reduce overfitting.
  """

  alias PvForecast.Model
  alias PvForecast.Utils

  @current_ensemble_version "1.0.0"
  @compatible_versions ["1.0.0"]

  # Configuration for different models in the ensemble
  @ensemble_configs [
    %{
      name: "model_1",
      hidden_layers: [32, 16, 8],
      dropout_rate: 0.2,
      learning_rate: 0.01,
      seed: 42
    },
    %{
      name: "model_2",
      hidden_layers: [40, 20, 10],
      dropout_rate: 0.1,
      learning_rate: 0.05,
      seed: 123
    },
    %{
      name: "model_3",
      hidden_layers: [16, 8],
      dropout_rate: 0.2,
      learning_rate: 0.01,
      seed: 456
    }
  ]

  @doc """
  Trains an ensemble of neural networks with different configurations.

  Parameters:
    - input_data: Training input tensor
    - target_data: Training target tensor
    - opts: Training options (epochs, validation_split, etc.)

  Returns:
    - %{models: list_of_trained_models, metadata: ensemble_metadata}
  """
  def train_ensemble(input_data, target_data, opts \\ []) do
    epochs = Keyword.get(opts, :epochs, 100)
    validation_split = Keyword.get(opts, :validation_split, 0.2)
    early_stopping_patience = Keyword.get(opts, :early_stopping_patience, 10)

    IO.puts("Training ensemble of #{length(@ensemble_configs)} models...")

    # Split data once for all models to ensure consistent validation
    {train_inputs, train_targets, val_inputs, val_targets} =
      Model.train_val_split(input_data, target_data, 1.0 - validation_split)

    val_data = [{val_inputs, val_targets}]
    train_data = [{train_inputs, train_targets}]

    # Train each model in the ensemble
    trained_models =
      @ensemble_configs
      |> Enum.with_index(1)
      |> Enum.map(fn {config, index} ->
        IO.puts("Training model #{index}/#{length(@ensemble_configs)}: #{config.name}")

        # Set random seed for reproducible results
        :rand.seed(:default, config.seed)

        # Build model with custom configuration
        model = build_model_with_config(config)

        # Create optimizer with custom learning rate
        optimizer = Polaris.Optimizers.adam(learning_rate: config.learning_rate)

        # Train the model
        trained_state =
          model
          |> Axon.Loop.trainer(:mean_squared_error, optimizer)
          |> Axon.Loop.metric(:mean_absolute_error, "MAE")
          |> Axon.Loop.validate(model, val_data)
          |> Axon.Loop.early_stop("validation_loss",
            mode: :min,
            patience: early_stopping_patience
          )
          |> Axon.Loop.run(train_data, Axon.ModelState.empty(),
            epochs: epochs,
            compiler: EXLA
          )

        # Return trained model with metadata
        %{
          name: config.name,
          model: model,
          params: trained_state,
          config: config,
          validation_data: %{
            inputs: val_inputs,
            targets: val_targets
          }
        }
      end)

    IO.puts("Ensemble training completed!")

    # Return ensemble
    %{
      models: trained_models,
      metadata: %{
        ensemble_size: length(@ensemble_configs),
        version: @current_ensemble_version,
        training_samples: Nx.axis_size(train_inputs, 0),
        validation_samples: Nx.axis_size(val_inputs, 0),
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Evaluates the ensemble performance on validation data.
  """
  def evaluate_ensemble(ensemble) do
    %{models: trained_models} = ensemble

    # Use validation data from first model (they should all be the same)
    case List.first(trained_models) do
      %{validation_data: %{inputs: val_inputs, targets: val_targets}} ->
        # Get ensemble predictions
        ensemble_predictions = predict_ensemble(ensemble, val_inputs)

        # Calculate ensemble metrics
        mse = Nx.mean(Nx.pow(Nx.subtract(ensemble_predictions, val_targets), 2))
        mae = Nx.mean(Nx.abs(Nx.subtract(ensemble_predictions, val_targets)))

        # R² score
        ss_res = Nx.sum(Nx.pow(Nx.subtract(val_targets, ensemble_predictions), 2))
        ss_tot = Nx.sum(Nx.pow(Nx.subtract(val_targets, Nx.mean(val_targets)), 2))
        r_squared = Nx.subtract(1.0, Nx.divide(ss_res, ss_tot))

        # Also evaluate individual models for comparison
        individual_metrics =
          Enum.map(trained_models, fn trained_model ->
            individual_pred =
              Axon.predict(
                trained_model.model,
                trained_model.params,
                %{"features" => val_inputs}
              )

            ind_mse = Nx.mean(Nx.pow(Nx.subtract(individual_pred, val_targets), 2))
            ind_mae = Nx.mean(Nx.abs(Nx.subtract(individual_pred, val_targets)))

            %{
              name: trained_model.name,
              mse: Nx.to_number(ind_mse),
              mae: Nx.to_number(ind_mae),
              rmse: :math.sqrt(Nx.to_number(ind_mse))
            }
          end)

        ensemble_metrics = %{
          mse: Nx.to_number(mse),
          mae: Nx.to_number(mae),
          rmse: :math.sqrt(Nx.to_number(mse)),
          r_squared: Nx.to_number(r_squared)
        }

        {:ok,
         %{
           ensemble: ensemble_metrics,
           individual_models: individual_metrics
         }}

      _ ->
        {:error, "No validation data available in ensemble"}
    end
  end

  @doc """
  Makes predictions using the ensemble of trained models.

  Parameters:
    - ensemble: Trained ensemble returned by train_ensemble/3
    - new_data: Input tensor for prediction
    - opts: Prediction options (combination_method, weights, etc.)

  Returns:
    - Tensor with ensemble predictions
  """
  def predict_ensemble(ensemble, new_data, opts \\ []) do
    combination_method = Keyword.get(opts, :combination_method, :average)
    model_weights = Keyword.get(opts, :weights, nil)

    %{models: trained_models} = ensemble

    # Validate input data shape (same as individual model)
    input_shape = Nx.shape(new_data)
    expected_features = 4

    new_data =
      case input_shape do
        {_batch_size, ^expected_features} ->
          new_data

        {^expected_features} ->
          Nx.reshape(new_data, {1, expected_features})

        _ ->
          raise ArgumentError,
                "Input data must have shape {batch_size, #{expected_features}} or {#{expected_features}}, got #{inspect(input_shape)}"
      end

    # Get predictions from each model
    predictions =
      Enum.map(trained_models, fn trained_model ->
        %{model: model, params: params} = trained_model
        Axon.predict(model, params, %{"features" => new_data})
      end)

    # Combine predictions based on method
    case combination_method do
      :average ->
        # Simple average of all predictions
        predictions
        |> Enum.reduce(&Nx.add/2)
        |> Nx.divide(length(predictions))

      :weighted_average when is_list(model_weights) ->
        # Weighted average using provided weights
        if length(model_weights) != length(predictions) do
          raise ArgumentError, "Number of weights must match number of models"
        end

        weighted_sum =
          predictions
          |> Enum.zip(model_weights)
          |> Enum.reduce(Nx.tensor(0.0), fn {pred, weight}, acc ->
            Nx.add(acc, Nx.multiply(pred, weight))
          end)

        # Normalize by sum of weights
        weight_sum = Enum.sum(model_weights)
        Nx.divide(weighted_sum, weight_sum)

      _ ->
        raise ArgumentError, "Unsupported combination method: #{combination_method}"
    end
  end

  @doc """
  Helper function for single prediction using ensemble.
  """
  def predict_single_ensemble(ensemble, max_temp, sunshine_hours, rain_mm, date, opts \\ []) do
    input_tensor =
      Nx.tensor(
        [
          Model.features(%{
            date: date,
            max_temp: max_temp,
            sunshine_hours: sunshine_hours,
            rain_mm: rain_mm
          })
        ],
        type: :f32
      )

    prediction = predict_ensemble(ensemble, input_tensor, opts)
    # Squeeze to remove batch dimension for single predictions
    Nx.squeeze(prediction)
  end

  @doc """
  Saves the trained ensemble to disk.

  Options:
    - description: Free text stored in the metadata
    - metrics: Evaluation metrics (e.g. from evaluate_ensemble/1) stored in the metadata
  """
  def save_ensemble(ensemble, filepath, opts \\ []) do
    description = Keyword.get(opts, :description, "PV forecast ensemble model")
    metrics = Keyword.get(opts, :metrics)

    serializable_ensemble = %{
      version: @current_ensemble_version,
      ensemble_size: length(ensemble.models),
      models:
        Enum.map(ensemble.models, fn model ->
          %{
            name: model.name,
            # Copy params off the EXLA device, otherwise only buffer references get serialized
            params: Nx.backend_copy(model.params, Nx.BinaryBackend),
            config: model.config
          }
        end),
      metadata:
        ensemble.metadata
        |> Map.put(:description, description)
        |> Map.put(:metrics, metrics)
    }

    binary_data = :erlang.term_to_binary(serializable_ensemble, [:compressed])

    case File.write(filepath, binary_data) do
      :ok -> {:ok, "Ensemble saved to #{filepath}"}
      {:error, reason} -> {:error, "Failed to save ensemble: #{reason}"}
    end
  end

  @doc """
  Loads a trained ensemble from disk.

  Options:
    - strict_validation: When true (default), an ensemble saved with an incompatible
      version or an inconsistent model count is rejected. When false, it is loaded
      anyway and a warning is logged.
  """
  def load_ensemble(filepath, opts \\ []) do
    strict_validation = Keyword.get(opts, :strict_validation, true)

    case File.read(filepath) do
      {:ok, binary_data} ->
        try do
          serializable_ensemble = :erlang.binary_to_term(binary_data)

          with :ok <- validate_ensemble(serializable_ensemble, strict_validation) do
            # Reconstruct the ensemble
            models =
              Enum.map(serializable_ensemble.models, fn serialized_model ->
                %{
                  name: serialized_model.name,
                  model: build_model_with_config(serialized_model.config),
                  params: serialized_model.params,
                  config: serialized_model.config
                }
              end)

            ensemble = %{
              models: models,
              metadata: serializable_ensemble.metadata
            }

            {:ok, ensemble}
          end
        rescue
          error -> {:error, "Failed to deserialize ensemble: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read ensemble file: #{reason}"}
    end
  end

  # Unbuildable models are always an error, version/size mismatches only when strict
  defp validate_ensemble(%{version: version, models: [_ | _] = models} = serialized, strict) do
    if Enum.all?(models, &match?(%{config: %{hidden_layers: _, dropout_rate: _}}, &1)) do
      problems =
        [
          if version not in @compatible_versions do
            "version #{inspect(version)} is not one of #{inspect(@compatible_versions)}"
          end,
          if Map.get(serialized, :ensemble_size) != length(models) do
            "ensemble size #{inspect(Map.get(serialized, :ensemble_size))} does not match #{length(models)} saved models"
          end
        ]
        |> Enum.reject(&is_nil/1)

      Utils.check_compatibility("ensemble", problems, strict)
    else
      {:error, "Invalid ensemble file, model config without hidden_layers/dropout_rate"}
    end
  end

  defp validate_ensemble(_serialized, _strict) do
    {:error, "Invalid ensemble file, missing version or models"}
  end

  # Build model with custom configuration
  defp build_model_with_config(config) do
    %{hidden_layers: layers, dropout_rate: dropout_rate} = config

    # Start with input layer and normalization
    model =
      Axon.input("features", shape: {nil, 4})
      |> Axon.layer_norm()

    # Add hidden layers dynamically
    model =
      Enum.reduce(layers, model, fn layer_size, acc ->
        acc
        |> Axon.dense(layer_size, activation: :relu)
        |> Axon.dropout(rate: dropout_rate)
      end)

    # Output layer
    model |> Axon.dense(1, activation: :linear)
  end
end
