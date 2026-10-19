defmodule PvForecast.EnsembleTest do
  use ExUnit.Case, async: false

  alias PvForecast.Ensemble
  alias PvForecast.Model
  alias PvForecast.TestFixtures

  test "saved ensemble contains the weights, not device buffer references" do
    path = TestFixtures.ensemble_path()

    %{models: models} = path |> File.read!() |> :erlang.binary_to_term()

    for %{params: params} <- models do
      backends =
        Nx.Defn.Composite.reduce(params, MapSet.new(), fn tensor, acc ->
          MapSet.put(acc, tensor.data.__struct__)
        end)

      assert backends == MapSet.new([Nx.BinaryBackend])
    end
  end

  test "loaded ensemble predicts" do
    {:ok, ensemble} = Ensemble.load_ensemble(TestFixtures.ensemble_path())

    prediction = Ensemble.predict_single_ensemble(ensemble, 20.0, 8.0, 0.0, ~D[2026-06-21])

    assert is_float(Nx.to_number(prediction))
  end

  test "features/1 matches the training feature order" do
    day = %{date: ~D[2026-06-21], max_temp: 20.0, sunshine_hours: 8.0, rain_mm: 1.5}

    assert [20.0, 8.0, 1.5, declination] = Model.features(day)
    assert_in_delta declination, 23.45, 0.1
  end
end
