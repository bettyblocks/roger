defmodule RogerTest do
  use ExUnit.Case
  doctest Roger

  @app "test#{:erlang.monotonic_time}"

  test "predefined partitions get started automatically" do

    :ok = Application.stop :roger

    app_atom = String.to_atom(@app)
    Application.put_env(:roger, :partitions, [{app_atom, [default: 10, other: 2]}])

    :ok = Application.start :roger

    :timer.sleep 200

    apps = Roger.NodeInfo.running_partitions
    assert apps[@app] != nil
    assert is_map(apps[@app])
    assert 2 == Map.values(apps[@app]) |> Enum.count
    assert is_map(apps[@app][:default])
    assert is_map(apps[@app][:other])

    assert 10 == apps[@app][:default].max_workers
    assert 2 == apps[@app][:other].max_workers

  end

end
