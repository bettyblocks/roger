defmodule Roger.Partition.NodeInfoTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.NodeInfo
  alias Roger.Partition.Consumer

  defmodule SlowTestJob do
    use Job

    def perform(queue) do
      :timer.sleep 200
      send(Roger.Partition.NodeInfoTest, {:done, queue})
    end
  end

  test "get partition info" do
    assert %{waiting: w, running: r} = NodeInfo.partitions
    assert is_map(w)
    assert is_map(r)
  end

  test "get the running jobs" do
    :ok = Consumer.resume(@app, :default)

    {:ok, job} = Job.create(SlowTestJob, 1)
    :ok = Job.enqueue(job, "test")
    :timer.sleep 10

    info = NodeInfo.running_jobs
    assert info["test"] == NodeInfo.running_jobs("test")

    assert is_map(info)
    assert is_list(info["test"])
    jobs = info["test"]

    assert 1 == Enum.count(jobs)
    job = jobs |> hd

    assert job.started_at > 0
    assert (Roger.now - job.started_at) > 0
    assert job.module == SlowTestJob
    assert job.args == 1

    assert_receive {:done, 1}, 500
    :timer.sleep 10

    assert [] == NodeInfo.running_jobs()["test"]
    assert [] == NodeInfo.running_jobs("test")
  end

  test "queue info" do
    :ok = Consumer.pause(@app, :default)

    {:ok, job} = Job.create(SlowTestJob, 4)
    :ok = Job.enqueue(job, "test")
    :timer.sleep 10

    info = NodeInfo.running_partitions

    partition = info["test"]
    assert partition[:default][:consumer_count] == 0 # we're paused
    assert partition[:default][:max_workers] == 10
    assert partition[:default][:message_count] > 0
    assert partition[:default][:paused] == true

    :ok = Consumer.resume(@app, :default)
    assert_receive {:done, 4}, 500
  end

  test "queue info for consumer without workers" do

    {:ok, _pid} = Roger.Partition.start("idle", default: 0)

    {:ok, job} = Job.create(SlowTestJob, 5)
    :ok = Job.enqueue(job, "idle")
    {:ok, job} = Job.create(SlowTestJob, 5)
    :ok = Job.enqueue(job, "idle")

    :timer.sleep 100

    info = NodeInfo.running_partitions

    partition = info["idle"]
    assert partition[:default][:consumer_count] == 0 # we're not consuming this queue
    assert partition[:default][:max_workers] == 0
    assert partition[:default][:message_count] > 0
    assert partition[:default][:paused] == false

    :ok = Roger.Partition.reconfigure("idle", default: 1)

    info = NodeInfo.running_partitions

    partition = info["idle"]
    assert partition[:default][:consumer_count] == 1 # we're consuming
    assert partition[:default][:max_workers] == 1
    assert partition[:default][:message_count] > 0
    assert partition[:default][:paused] == false

    for _ <- 1..2 do
      assert_receive {:done, 5}, 500
    end

  end


  test "retrieve queued jobs" do
    :ok = Consumer.pause(@app, :default)

    apps = NodeInfo.running_partitions

    assert apps[@app].default.paused

    {:ok, job} = Job.create(SlowTestJob, 2)
    :ok = Job.enqueue(job, "test")

    {:ok, job} = Job.create(SlowTestJob, 3)
    :ok = Job.enqueue(job, "test")
    :timer.sleep 10

    apps = NodeInfo.running_partitions
    q = apps[@app].default

    assert q.message_count == 2
    assert q.consumer_count == 0

    jobs = NodeInfo.queued_jobs("test", :default)
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
