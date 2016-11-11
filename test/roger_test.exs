defmodule RogerTest do
  use ExUnit.Case
  doctest Roger


  test "predefined partitions get started automatically" do

    :ok = Application.stop :roger

    Application.put_env(:roger, :partitions, test: [default: 10, other: 2])

    :ok = Application.start :roger

    :timer.sleep 200

    apps = Roger.NodeInfo.running_partitions
    assert apps["test"] != nil
    assert is_map(apps["test"])
    assert 2 == Map.values(apps["test"]) |> Enum.count
    assert is_map(apps["test"][:default])
    assert is_map(apps["test"][:other])

    assert 10 == apps["test"][:default].max_workers
    assert 2 == apps["test"][:other].max_workers

  end

end
