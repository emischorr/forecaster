defmodule PvForecast.ModelTest do
  use ExUnit.Case, async: true

  alias PvForecast.Model

  @moduletag :tmp_dir

  defp write_model(dir, changes, drop \\ []) do
    path = Path.join(dir, "model.bin")

    %{
      model_version: "1.0.0",
      compatible_versions: ["1.0.0"],
      model_config: %{type: "pv_forecast", features: 4},
      params: Axon.ModelState.empty(),
      metadata: %{description: "test model"}
    }
    |> Map.merge(changes)
    |> Map.drop(drop)
    |> :erlang.term_to_binary()
    |> then(&File.write!(path, &1))

    path
  end

  test "loads a compatible model", %{tmp_dir: dir} do
    assert {:ok, %{model_version: "1.0.0"}} = dir |> write_model(%{}) |> Model.load_model()
  end

  test "rejects an incompatible version unless strict validation is off", %{tmp_dir: dir} do
    path = write_model(dir, %{model_version: "0.1.0"})

    assert {:error, "Incompatible model: version \"0.1.0\"" <> _} = Model.load_model(path)

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:ok, %{model_version: "0.1.0"}} = Model.load_model(path, strict_validation: false)
    end)
  end

  test "rejects a different feature configuration", %{tmp_dir: dir} do
    path = write_model(dir, %{model_config: %{type: "pv_forecast", features: 5}})

    assert {:error, "Incompatible model: model config" <> _} = Model.load_model(path)
  end

  test "always rejects a file without params", %{tmp_dir: dir} do
    path = write_model(dir, %{}, [:params])

    assert {:error, "Invalid model file, missing [:params]"} =
             Model.load_model(path, strict_validation: false)
  end
end
