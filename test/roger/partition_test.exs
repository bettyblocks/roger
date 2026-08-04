defmodule Roger.PartitionTest do
  use ExUnit.Case

  @app "test#{:erlang.monotonic_time()}"

  alias Roger.{NodeInfo, Partition, PartitionSupervisor}

  test "start and stop partition" do
    {:ok, _pid} = Partition.start(@app, default: 10)

    assert has_test_app(NodeInfo.running_partitions())

    :ok = Partition.stop(@app)

    assert await(fn -> !has_test_app(NodeInfo.running_partitions()) end)
  end

  test "automatic restart after supervisor stop" do
    {:ok, pid} = Partition.start(@app, default: 10)

    :ok = PartitionSupervisor.stop_child(pid)

    assert await(fn ->
             !has_test_app(NodeInfo.running_partitions()) and
               has_test_app(NodeInfo.waiting_partitions())
           end)

    # it restarts
    assert await(
             fn ->
               has_test_app(NodeInfo.running_partitions()) and
                 !has_test_app(NodeInfo.waiting_partitions())
             end,
             8_000
           )

    :ok = Partition.stop(@app)
  end

  @app2 "test#{:erlang.monotonic_time()}"

  test "test start / stop / start" do
    queues = [{:default, 20}, {:expression, 0}, {:fast, 20}]
    {:ok, _} = Partition.start(@app2, queues)
    Partition.stop(@app2)
    {:ok, _} = Partition.start(@app2, queues)

    :ok = Partition.stop(@app2)
  end

  defp has_test_app(apps) do
    apps[@app] != nil
  end

  # Partitions start and stop asynchronously, so poll for the expected state
  # instead of assuming a fixed amount of time is always enough.
  defp await(fun, timeout \\ 1_000) do
    cond do
      fun.() -> true
      timeout <= 0 -> false
      true ->
        :timer.sleep(25)
        await(fun, timeout - 25)
    end
  end
end
