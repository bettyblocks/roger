defmodule Roger.PartitionTest do
  use ExUnit.Case

  @app "test#{:erlang.monotonic_time}"

  alias Roger.{NodeInfo, Partition, PartitionSupervisor}

  test "start and stop partition" do

    {:ok, _pid} = Partition.start(@app, [default: 10])

    assert has_test_app(NodeInfo.running_partitions)

    :ok = Partition.stop(@app)
    :timer.sleep 50

    assert !has_test_app(NodeInfo.running_partitions)
  end

  test "automatic restart after supervisor stop" do

    {:ok, pid} = Partition.start(@app, [default: 10])

    :ok = PartitionSupervisor.stop_child(pid)

    :timer.sleep 50

    assert !has_test_app(NodeInfo.running_partitions)
    assert has_test_app(NodeInfo.waiting_partitions)

    :timer.sleep 4000
    # it restarts

    assert has_test_app(NodeInfo.running_partitions)
    assert !has_test_app(NodeInfo.waiting_partitions)

    :ok = Partition.stop(@app)
  end

  @app2 "test#{:erlang.monotonic_time}"

  test "test start / stop / start" do
    queues = [{:default,20},{:expression,0},{:fast,20}]
    {:ok, _} = Partition.start(@app2, queues)
    Partition.stop(@app2)
    {:ok, _} = Partition.start(@app2, queues)

    :ok = Partition.stop(@app2)
  end

  defp has_test_app(apps) do
    apps[@app] != nil
  end

end
