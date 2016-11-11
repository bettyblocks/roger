defmodule Roger.PartitionTest do
  use ExUnit.Case

  alias Roger.{NodeInfo, Partition, PartitionSupervisor}

  test "start and stop partition" do

    {:ok, _pid} = Partition.start("test", [default: 10])

    assert has_test_app(NodeInfo.running_partitions)

    :ok = Partition.stop("test")
    :timer.sleep 50

    assert !has_test_app(NodeInfo.running_partitions)
  end

  test "automatic restart after supervisor stop" do

    {:ok, pid} = Partition.start("test", [default: 10])

    :ok = PartitionSupervisor.stop_child(pid)
    :timer.sleep 50


    assert !has_test_app(NodeInfo.running_partitions)
    assert has_test_app(NodeInfo.waiting_partitions)

    :timer.sleep 1000
    # it restarts

    assert has_test_app(NodeInfo.running_partitions)
    assert !has_test_app(NodeInfo.waiting_partitions)

  end

  defp has_test_app(apps) do
    apps["test"] != nil
  end

end
