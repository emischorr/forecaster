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

  describe "load_ensemble/2 validation" do
    @describetag :tmp_dir

    defp write_modified_fixture(dir, changes) do
      path = Path.join(dir, "ensemble.bin")

      TestFixtures.ensemble_path()
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Map.merge(changes)
      |> :erlang.term_to_binary()
      |> then(&File.write!(path, &1))

      path
    end

    test "rejects an incompatible version unless strict validation is off", %{tmp_dir: dir} do
      path = write_modified_fixture(dir, %{version: "0.1.0"})

      assert {:error, "Incompatible ensemble: version \"0.1.0\"" <> _} =
               Ensemble.load_ensemble(path)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{models: [_ | _]}} = Ensemble.load_ensemble(path, strict_validation: false)
      end)
    end

    test "rejects a mismatching ensemble size", %{tmp_dir: dir} do
      path = write_modified_fixture(dir, %{ensemble_size: 7})

      assert {:error, "Incompatible ensemble: ensemble size 7" <> _} =
               Ensemble.load_ensemble(path)
    end

    test "always rejects an ensemble without models", %{tmp_dir: dir} do
      path = write_modified_fixture(dir, %{models: []})

      assert {:error, "Invalid ensemble file" <> _} =
               Ensemble.load_ensemble(path, strict_validation: false)
    end
  end

  test "features/1 matches the training feature order" do
    day = %{date: ~D[2026-06-21], max_temp: 20.0, sunshine_hours: 8.0, rain_mm: 1.5}

    assert [20.0, 8.0, 1.5, declination] = Model.features(day)
    assert_in_delta declination, 23.45, 0.1
  end
end
