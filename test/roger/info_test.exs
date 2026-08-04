defmodule Roger.Partition.InfoTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.{Info, NodeInfo}
  alias Roger.Partition.Consumer

  test "get roger info over the entire cluster" do
    node = node()
    assert [{^node, _}] = Info.partitions()
    assert [{^node, _}] = Info.running_partitions()
    assert [{^node, _}] = Info.waiting_partitions()
    assert [{^node, _}] = Info.running_jobs()
  end

  defmodule SlowTestJob do
    use Job

    def perform(queue) do
      :timer.sleep(300)
      send(Roger.Partition.InfoTest, {:done, queue})
    end
  end

  test "retrieve queued jobs" do
    :ok = Consumer.pause(@app, :default)

    assert NodeInfo.running_partitions()[@app].default.paused

    {:ok, job} = Job.create(SlowTestJob, 2)
    :ok = Job.enqueue(job, @app)

    {:ok, job} = Job.create(SlowTestJob, 3)
    :ok = Job.enqueue(job, @app)

    # Pausing nacks the jobs that were already handed to the consumer, so wait
    # until both are back in the queue and the consumer is gone.
    q = await_queue(message_count: 2, consumer_count: 0)

    assert q.message_count == 2
    assert q.consumer_count == 0

    # A quorum queue does not necessarily put a requeued message back in its
    # original position, so don't assume an order here.
    jobs = Info.queued_jobs(@app, :default)
    assert [a, b] = jobs
    assert Enum.sort([a.args, b.args]) == [2, 3]

    assert a.queued_at > 0
    assert a.started_at == 0

    :ok = Consumer.resume(@app, :default)
    assert_receive {:done, 2}, 2_000
    assert_receive {:done, 3}, 2_000
  end

  defp await_queue(expected, tries \\ 200) do
    q = NodeInfo.running_partitions()[@app].default

    if tries == 0 or Enum.all?(expected, fn {key, value} -> Map.get(q, key) == value end) do
      q
    else
      :timer.sleep(10)
      await_queue(expected, tries - 1)
    end
  end
end
