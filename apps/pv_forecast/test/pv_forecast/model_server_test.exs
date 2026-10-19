defmodule PvForecast.ModelServerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PvForecast.ModelServer
  alias PvForecast.TestFixtures

  test "serves predictions from a valid model file" do
    server = start_supervised!({ModelServer, path: TestFixtures.ensemble_path(), name: nil})

    assert %{status: :ready, metadata: %{ensemble_size: 3}} = ModelServer.info(server)

    inputs = Nx.tensor([[20.0, 8.0, 0.0, 23.4], [5.0, 0.0, 10.0, -23.4]], type: :f32)
    assert {:ok, %{mean: [_, _] = mean, min: min, max: max}} = ModelServer.predict(inputs, server)

    for {lo, avg, hi} <- Enum.zip([min, mean, max]) do
      assert 0.0 <= lo and lo <= avg and avg <= hi
    end
  end

  test "is not ready when the model file is missing" do
    capture_log(fn ->
      server = start_supervised!({ModelServer, path: "tmp/test/nope.bin", name: nil})

      assert %{status: :not_ready} = ModelServer.info(server)
      assert {:error, :not_ready} = ModelServer.predict(Nx.iota({1, 4}), server)
    end)
  end

  test "reload picks up a model file that appeared after startup" do
    path = "tmp/test/reload.bin"
    File.rm(path)

    capture_log(fn ->
      server = start_supervised!({ModelServer, path: path, name: nil})
      assert %{status: :not_ready} = ModelServer.info(server)
      assert {:error, _} = ModelServer.reload(server)

      File.cp!(TestFixtures.ensemble_path(), path)
      assert :ok = ModelServer.reload(server)
      assert %{status: :ready} = ModelServer.info(server)
    end)
  end

  test "is not ready for files that hold only device buffer references" do
    path = "tmp/test/dangling.bin"

    %{models: models} =
      ensemble = TestFixtures.ensemble_path() |> File.read!() |> :erlang.binary_to_term()

    # Simulates the old save format: params still on the EXLA device
    dangling =
      for model <- models do
        params = Nx.backend_transfer(model.params, EXLA.Backend)
        Nx.Defn.Composite.traverse(params, &Nx.backend_deallocate/1)
        %{model | params: params}
      end

    File.write!(path, :erlang.term_to_binary(%{ensemble | models: dangling}))

    capture_log(fn ->
      server = start_supervised!({ModelServer, path: path, name: nil})
      assert %{status: :not_ready, reason: reason} = ModelServer.info(server)
      assert reason =~ "retrain"
    end)
  end
end
