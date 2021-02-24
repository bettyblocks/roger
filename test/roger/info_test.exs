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
    :timer.sleep(50)

    q = NodeInfo.running_partitions()[@app].default

    assert q.message_count == 2
    assert q.consumer_count == 0

    jobs = Info.queued_jobs(@app, :default)
    assert [a, b] = jobs
    assert a.args == 3
    assert b.args == 2

    assert a.queued_at > 0
    assert a.started_at == 0

    :ok = Consumer.resume(@app, :default)
    assert_receive {:done, 2}, 500
    assert_receive {:done, 3}, 500
  end
end
