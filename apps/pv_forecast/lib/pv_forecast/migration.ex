defmodule PvForecast.Migration do
  # Migration functions for different version upgrades
  def migrate_model(old_model, target_version) do
    current_version = Map.get(old_model, :model_version, "1.0.0")

    cond do
      current_version == target_version ->
        # No migration needed
        {:ok, old_model}

      can_migrate?(current_version, target_version) ->
        perform_migration(old_model, current_version, target_version)

      true ->
        {:error, "Cannot migrate from version #{current_version} to #{target_version}"}
    end
  end

  defp can_migrate?(from_version, to_version) do
    # Define migration paths
    migration_paths = %{
      {"1.0.0", "1.1.0"} => :add_humidity,
      {"1.1.0", "2.0.0"} => :add_weather_features,
      # Multi-step migration
      {"1.0.0", "2.0.0"} => :full_upgrade
    }

    Map.has_key?(migration_paths, {from_version, to_version})
  end

  defp perform_migration(old_model, from_version, to_version) do
    IO.puts("Migrating model from v#{from_version} to v#{to_version}...")

    case {from_version, to_version} do
      {"1.0.0", "1.1.0"} ->
        migrate_add_humidity(old_model)

      {"1.1.0", "2.0.0"} ->
        migrate_add_weather_features(old_model)

      {"1.0.0", "2.0.0"} ->
        # Multi-step migration
        with {:ok, v1_1_model} <- migrate_add_humidity(old_model),
             {:ok, v2_0_model} <- migrate_add_weather_features(v1_1_model) do
          {:ok, v2_0_model}
        end

      _ ->
        {:error, "Migration path not implemented"}
    end
  end

  # Migration: Add humidity feature (v1.0.0 → v1.1.0)
  defp migrate_add_humidity(old_model) do
    IO.puts("⚠ Migration requires retraining - adding humidity feature")
    IO.puts("Old normalization stats will be preserved for existing features")

    # Extract old normalization stats
    old_input_stats = old_model.input_stats

    # Create placeholder stats for new humidity feature
    # These should be replaced when retraining with humidity data
    # Typical humidity %
    humidity_mean = Nx.tensor([50.0])
    # Typical humidity std
    humidity_std = Nx.tensor([20.0])

    # Extend normalization statistics
    new_input_mean = Nx.concatenate([old_input_stats.mean, humidity_mean])
    new_input_std = Nx.concatenate([old_input_stats.std, humidity_std])

    migrated_model = %{
      old_model
      | model_version: "1.1.0",
        input_stats: %{mean: new_input_mean, std: new_input_std},
        metadata: Map.put(old_model.metadata, :migration_required, true)
    }

    {:ok, migrated_model}
  end

  # Migration: Add wind_speed and cloud_cover (v1.1.0 → v2.0.0)
  defp migrate_add_weather_features(old_model) do
    IO.puts("⚠ Migration requires retraining - adding wind_speed and cloud_cover")

    old_input_stats = old_model.input_stats

    # Placeholder stats for new features
    # km/h
    wind_mean = Nx.tensor([10.0])
    wind_std = Nx.tensor([5.0])
    # % coverage
    cloud_mean = Nx.tensor([50.0])
    cloud_std = Nx.tensor([30.0])

    new_input_mean = Nx.concatenate([old_input_stats.mean, wind_mean, cloud_mean])
    new_input_std = Nx.concatenate([old_input_stats.std, wind_std, cloud_std])

    migrated_model = %{
      old_model
      | model_version: "2.0.0",
        input_stats: %{mean: new_input_mean, std: new_input_std},
        metadata: Map.put(old_model.metadata, :migration_required, true)
    }

    {:ok, migrated_model}
  end
end
