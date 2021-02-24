defmodule Roger.Partition.QueueTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.{Info, NodeInfo, Queue}
  alias Roger.Partition.Consumer

  defmodule TestJob do
    use Job

    def perform(queue) do
      :timer.sleep(200)
      send(Roger.Partition.InfoTest, {:done, queue})
    end
  end

  test "purge queued jobs" do
    :ok = Consumer.pause(@app, :default)
    {:ok, job} = Job.create(TestJob, 2)
    :ok = Job.enqueue(job, @app)

    {:ok, job} = Job.create(TestJob, 3)
    :ok = Job.enqueue(job, @app)

    :timer.sleep(100)

    assert 2 == NodeInfo.running_partitions()[@app].default.message_count

    jobs = Info.queued_jobs(@app, :default)
    assert [_, _] = jobs

    {:ok, %{message_count: 2}} = Queue.purge(@app, :default)

    assert 0 == NodeInfo.running_partitions()[@app].default.message_count

    :ok = Consumer.resume(@app, :default)
  end
end
